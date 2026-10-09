import SwiftUI
import UIKit

/// A UIKit surface keeps every finger independent, including slides between notes.
@MainActor
struct TouchKeyboard: UIViewRepresentable {
    var baseNote: Int
    var octaves: Int = 2
    var onNoteOn: (Int, Float) -> Void
    var onNoteOff: (Int) -> Void

    func makeUIView(context: Context) -> KeyboardSurface {
        let view = KeyboardSurface()
        view.isMultipleTouchEnabled = true
        view.backgroundColor = .clear
        view.overrideUserInterfaceStyle = .light
        view.baseNote = baseNote
        view.octaves = octaves
        view.onNoteOn = onNoteOn
        view.onNoteOff = onNoteOff
        return view
    }

    func updateUIView(_ view: KeyboardSurface, context: Context) {
        view.onNoteOn = onNoteOn
        view.onNoteOff = onNoteOff
        if view.baseNote != baseNote || view.octaves != octaves {
            view.releaseAllNotes()
            view.baseNote = baseNote
            view.octaves = octaves
            view.setNeedsDisplay()
            view.rebuildAccessibility()
        }
    }

    static func dismantleUIView(_ view: KeyboardSurface, coordinator: ()) {
        view.releaseAllNotes()
    }
}

final class KeyboardSurface: UIView {
    var baseNote = 48
    var octaves = 2
    var onNoteOn: (Int, Float) -> Void = { _, _ in }
    var onNoteOff: (Int) -> Void = { _ in }
    private var fingers: [ObjectIdentifier: Int] = [:]
    private var accessibleNote: Int?
    private var accessibleGeneration: UInt = 0
    private var keyHighlights: [Int: CGFloat] = [:]
    private var keyTargets: [Int: CGFloat] = [:]
    private var keyAnimations: [Int: KeyAnimation] = [:]
    private var displayLink: CADisplayLink?
    private var animationDriver: KeyboardAnimationDriver?
    private let whiteSemitones = [0, 2, 4, 5, 7, 9, 11]
    private let blackOffsets: [(boundary: Int, semitone: Int)] = [(1, 1), (2, 3), (4, 6), (5, 8), (6, 10)]
    private let noteNames = ["C", "C sharp", "D", "D sharp", "E", "F", "F sharp", "G", "G sharp", "A", "A sharp", "B"]

    private struct KeyAnimation {
        let start: CFTimeInterval
        let duration: CFTimeInterval
        let from: CGFloat
        let to: CGFloat
    }

    private var whiteWidth: CGFloat { bounds.width / CGFloat(max(1, octaves * 7)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        setNeedsDisplay()
        rebuildAccessibility()
    }

    private func whiteRect(index: Int) -> CGRect {
        CGRect(x: CGFloat(index) * whiteWidth, y: 0, width: whiteWidth, height: bounds.height)
    }

    private func blackRect(octave: Int, boundary: Int) -> CGRect {
        let width = whiteWidth * 0.61
        return CGRect(x: CGFloat(octave * 7 + boundary) * whiteWidth - width / 2,
                      y: 0, width: width, height: bounds.height * 0.62)
    }

    private func note(at point: CGPoint) -> Int? {
        guard bounds.contains(point) else { return nil }
        for octave in 0..<octaves {
            for offset in blackOffsets {
                if blackRect(octave: octave, boundary: offset.boundary).contains(point) {
                    return baseNote + octave * 12 + offset.semitone
                }
            }
        }
        let index = min(octaves * 7 - 1, max(0, Int(point.x / whiteWidth)))
        return baseNote + (index / 7) * 12 + whiteSemitones[index % 7]
    }

    private func pressed(_ note: Int) -> Bool {
        fingers.values.contains(note) || accessibleNote == note
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let textFont = UIFont.systemFont(ofSize: min(11, whiteWidth * 0.4), weight: .medium)
        for index in 0..<(octaves * 7) {
            let midi = baseNote + (index / 7) * 12 + whiteSemitones[index % 7]
            let amount = keyHighlights[midi] ?? (pressed(midi) ? 1 : 0)
            var key = whiteRect(index: index).insetBy(dx: 0.8, dy: 0.6)
            key.size.height -= UIAccessibility.isReduceMotionEnabled ? 0 : amount * 2
            let path = UIBezierPath(roundedRect: key, cornerRadius: 8)
            blendedColor(from: (0.98, 0.985, 0.995), to: (0, 0.36, 0.88), amount: amount).setFill()
            path.fill()
            UIColor(red: 0.84, green: 0.86, blue: 0.89, alpha: 1 - amount * 0.7).setStroke()
            path.lineWidth = 0.65
            path.stroke()
            if index % 7 == 0 {
                let title = "C\(midi / 12 - 1)" as NSString
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: textFont,
                    .foregroundColor: blendedColor(from: (0.42, 0.45, 0.5), to: (1, 1, 1), amount: amount)
                ]
                let size = title.size(withAttributes: attributes)
                title.draw(at: CGPoint(x: key.midX - size.width / 2, y: key.maxY - size.height - 9), withAttributes: attributes)
            }
            if amount > 0 {
                context.setFillColor(UIColor.white.withAlphaComponent(amount * 0.9).cgColor)
                context.fillEllipse(in: CGRect(x: key.midX - 2, y: key.maxY - 28, width: 4, height: 4))
            }
        }
        for octave in 0..<octaves {
            for offset in blackOffsets {
                let midi = baseNote + octave * 12 + offset.semitone
                let amount = keyHighlights[midi] ?? (pressed(midi) ? 1 : 0)
                var key = blackRect(octave: octave, boundary: offset.boundary)
                key.size.height -= UIAccessibility.isReduceMotionEnabled ? 0 : amount * 1.5
                let path = UIBezierPath(roundedRect: key, cornerRadius: 6)
                context.saveGState()
                context.setShadow(offset: CGSize(width: 0, height: 2), blur: 3, color: UIColor.black.withAlphaComponent(0.13).cgColor)
                blendedColor(from: (0.16, 0.17, 0.19), to: (0, 0.36, 0.88), amount: amount).setFill()
                path.fill()
                context.restoreGState()
                let inset = key.insetBy(dx: 3, dy: 3)
                let highlight = UIBezierPath(roundedRect: CGRect(x: inset.minX, y: inset.minY, width: inset.width, height: inset.height - 5), cornerRadius: 3)
                UIColor.white.withAlphaComponent(0.045 + amount * 0.06).setFill()
                highlight.fill()
            }
        }
    }

    private func move(_ touch: UITouch, ending: Bool = false) {
        let identifier = ObjectIdentifier(touch)
        let previous = fingers[identifier]
        let next = ending ? nil : note(at: touch.location(in: self))
        guard previous != next else { return }
        fingers.removeValue(forKey: identifier)
        if let previous, !pressed(previous) { onNoteOff(previous) }
        if let next {
            let wasPressed = pressed(next)
            fingers[identifier] = next
            if !wasPressed {
                // A lower touch on the key produces a stronger note.
                let relativeY = Float(touch.location(in: self).y / max(1, bounds.height))
                onNoteOn(next, min(1, max(0.35, 0.55 + relativeY * 0.45)))
            }
        }
        updateKeyAnimations()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { touches.forEach { move($0) } }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { touches.forEach { move($0) } }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { touches.forEach { move($0, ending: true) } }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { touches.forEach { move($0, ending: true) } }

    func releaseAllNotes() {
        var notes = Set(fingers.values)
        if let accessibleNote { notes.insert(accessibleNote) }
        fingers.removeAll()
        accessibleNote = nil
        accessibleGeneration &+= 1
        notes.forEach(onNoteOff)
        // Release visuals and notes together; stale highlights must not survive an octave change.
        stopAnimation()
        keyHighlights.removeAll()
        keyTargets.removeAll()
        keyAnimations.removeAll()
        setNeedsDisplay()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { releaseAllNotes() }
    }

    func rebuildAccessibility() {
        isAccessibilityElement = false
        var elements: [UIAccessibilityElement] = []
        for semitone in 0..<(octaves * 12) {
            let midi = baseNote + semitone
            let element = PianoKeyAccessibilityElement(accessibilityContainer: self)
            element.accessibilityLabel = "\(noteNames[midi % 12]) \(midi / 12 - 1)"
            element.accessibilityHint = "Double tap to play a short note"
            element.accessibilityTraits = .button
            element.action = { [weak self] in self?.playAccessibleNote(midi) }
            let octave = semitone / 12
            if let whiteIndex = whiteSemitones.firstIndex(of: semitone % 12) {
                var key = whiteRect(index: octave * 7 + whiteIndex)
                key.origin.y = bounds.height * 0.63
                key.size.height = bounds.height * 0.37
                element.accessibilityFrameInContainerSpace = key
            } else if let offset = blackOffsets.first(where: { $0.semitone == semitone % 12 }) {
                element.accessibilityFrameInContainerSpace = blackRect(octave: octave, boundary: offset.boundary)
            }
            elements.append(element)
        }
        accessibilityElements = elements
    }

    private func playAccessibleNote(_ note: Int) {
        accessibleGeneration &+= 1
        let generation = accessibleGeneration
        if let old = accessibleNote {
            accessibleNote = nil
            if !pressed(old) { onNoteOff(old) }
        }
        let wasPressed = pressed(note)
        accessibleNote = note
        if !wasPressed { onNoteOn(note, 0.8) }
        updateKeyAnimations()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.accessibleGeneration == generation, self.accessibleNote == note else { return }
            self.accessibleNote = nil
            if !self.pressed(note) { self.onNoteOff(note) }
            self.updateKeyAnimations()
        }
    }

    private func blendedColor(from: (CGFloat, CGFloat, CGFloat), to: (CGFloat, CGFloat, CGFloat), amount: CGFloat) -> UIColor {
        let value = min(1, max(0, amount))
        return UIColor(red: from.0 + (to.0 - from.0) * value,
                       green: from.1 + (to.1 - from.1) * value,
                       blue: from.2 + (to.2 - from.2) * value, alpha: 1)
    }

    private func updateKeyAnimations() {
        let now = CACurrentMediaTime()
        advanceKeyAnimations(at: now)
        for note in baseNote..<(baseNote + octaves * 12) {
            let target: CGFloat = pressed(note) ? 1 : 0
            guard keyTargets[note, default: 0] != target else { continue }
            keyTargets[note] = target
            if UIAccessibility.isReduceMotionEnabled {
                keyHighlights[note] = target
                keyAnimations.removeValue(forKey: note)
            } else {
                keyAnimations[note] = KeyAnimation(start: now, duration: target == 1 ? 0.09 : 0.18,
                                                   from: keyHighlights[note, default: 0], to: target)
            }
        }
        if keyAnimations.isEmpty {
            stopAnimation()
        } else if displayLink == nil {
            // The driver holds the keyboard weakly, so a display link cannot retain a closed screen.
            let driver = KeyboardAnimationDriver()
            driver.keyboard = self
            animationDriver = driver
            let link = CADisplayLink(target: driver, selector: #selector(KeyboardAnimationDriver.tick(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        setNeedsDisplay()
    }

    fileprivate func animationTick(_ link: CADisplayLink) {
        advanceKeyAnimations(at: CACurrentMediaTime())
        setNeedsDisplay()
        if keyAnimations.isEmpty { stopAnimation() }
    }

    private func advanceKeyAnimations(at time: CFTimeInterval) {
        var finished: [Int] = []
        for (note, animation) in keyAnimations {
            let progress = UIAccessibility.isReduceMotionEnabled ? 1 : min(1, max(0, (time - animation.start) / animation.duration))
            let eased = CGFloat(1 - pow(1 - progress, 3))
            keyHighlights[note] = animation.from + (animation.to - animation.from) * eased
            if progress >= 1 { finished.append(note) }
        }
        for note in finished { keyAnimations.removeValue(forKey: note) }
    }

    private func stopAnimation() {
        displayLink?.invalidate()
        displayLink = nil
        animationDriver = nil
    }
}

@MainActor
private final class KeyboardAnimationDriver: NSObject {
    weak var keyboard: KeyboardSurface?
    @objc func tick(_ link: CADisplayLink) {
        guard let keyboard else { link.invalidate(); return }
        keyboard.animationTick(link)
    }
}

private final class PianoKeyAccessibilityElement: UIAccessibilityElement {
    var action: () -> Void = {}
    override func accessibilityActivate() -> Bool { action(); return true }
}
