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
    private let whiteSemitones = [0, 2, 4, 5, 7, 9, 11]
    private let blackOffsets: [(boundary: Int, semitone: Int)] = [(1, 1), (2, 3), (4, 6), (5, 8), (6, 10)]
    private let noteNames = ["C", "C sharp", "D", "D sharp", "E", "F", "F sharp", "G", "G sharp", "A", "A sharp", "B"]

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
        let textFont = UIFont.monospacedSystemFont(ofSize: min(11, whiteWidth * 0.4), weight: .semibold)
        for index in 0..<(octaves * 7) {
            let key = whiteRect(index: index).insetBy(dx: 0.7, dy: 0.6)
            let midi = baseNote + (index / 7) * 12 + whiteSemitones[index % 7]
            let active = pressed(midi)
            let path = UIBezierPath(roundedRect: key, cornerRadius: 5)
            (active ? UIColor(red: 0.34, green: 0.94, blue: 0.79, alpha: 1) :
                UIColor(red: 0.87, green: 0.90, blue: 0.93, alpha: 1)).setFill()
            path.fill()
            if index % 7 == 0 {
                let title = "C\(midi / 12 - 1)" as NSString
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: textFont,
                    .foregroundColor: UIColor(red: 0.24, green: 0.31, blue: 0.36, alpha: 1)
                ]
                let size = title.size(withAttributes: attributes)
                title.draw(at: CGPoint(x: key.midX - size.width / 2, y: key.maxY - size.height - 9), withAttributes: attributes)
            }
            if active {
                context.setFillColor(UIColor(red: 0.05, green: 0.33, blue: 0.29, alpha: 0.7).cgColor)
                context.fillEllipse(in: CGRect(x: key.midX - 2.5, y: key.maxY - 29, width: 5, height: 5))
            }
        }
        for octave in 0..<octaves {
            for offset in blackOffsets {
                let key = blackRect(octave: octave, boundary: offset.boundary)
                let midi = baseNote + octave * 12 + offset.semitone
                let active = pressed(midi)
                let path = UIBezierPath(roundedRect: key, cornerRadius: 4)
                (active ? UIColor(red: 0.64, green: 0.51, blue: 1, alpha: 1) :
                    UIColor(red: 0.09, green: 0.12, blue: 0.18, alpha: 1)).setFill()
                path.fill()
                let inset = key.insetBy(dx: 3, dy: 3)
                let highlight = UIBezierPath(roundedRect: CGRect(x: inset.minX, y: inset.minY, width: inset.width, height: inset.height - 5), cornerRadius: 3)
                UIColor.white.withAlphaComponent(active ? 0.12 : 0.035).setFill()
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
        setNeedsDisplay()
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
        setNeedsDisplay()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.accessibleGeneration == generation, self.accessibleNote == note else { return }
            self.accessibleNote = nil
            if !self.pressed(note) { self.onNoteOff(note) }
            self.setNeedsDisplay()
        }
    }
}

private final class PianoKeyAccessibilityElement: UIAccessibilityElement {
    var action: () -> Void = {}
    override func accessibilityActivate() -> Bool { action(); return true }
}
