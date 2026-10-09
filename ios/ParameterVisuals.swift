import SwiftUI

/// Small, value-driven illustrations explain controls without adding another layer of knobs.
@MainActor
struct ParameterVisual: View {
    @ObservedObject var model: SynthModel
    let id: Int

    private let ink = Color(red: 0, green: 0.36, blue: 0.88)
    private let faint = Color(red: 0.78, green: 0.84, blue: 0.93)
    private var value: Float { model.value(id) }
    private var oscillator: Int { min(2, max(0, id / 32)) }
    private var oscillatorMode: Int { id < 96 ? Int(model.value(oscillator * 32)) : 0 }
    private var normalized: Double {
        guard let descriptor = ParameterCatalog.descriptor(id) else { return 0 }
        return Double(min(1, max(0, (value - descriptor.range.lowerBound) / (descriptor.range.upperBound - descriptor.range.lowerBound))))
    }

    var body: some View {
        Group {
            if id < 96 && id % 32 == 2 && oscillatorMode == 0 {
                SynthWaveform(table: Int(model.value(oscillator * 32 + 1)), position: value,
                              warp: model.value(oscillator * 32 + 9),
                              customTable: model.patch.wavetables.first { $0.oscillator == oscillator })
            } else {
                Canvas { context, size in draw(in: context, size: size) }
            }
        }
        .frame(height: 44)
        .accessibilityHidden(true)
    }

    var caption: String {
        if id < 96 {
            switch id % 32 {
            case 2:
                switch oscillatorMode {
                case 1: return "Where the one-shot starts."
                case 2: return "Where grains come from."
                case 3: return "Move through harmonic shapes."
                default: return "Move through wavetable frames."
                }
            case 3: return "This oscillator’s loudness."
            case 4: return "Transpose in semitones."
            case 5: return "Small pitch changes in cents."
            case 6: return oscillatorMode == 2 ? "Spread grains across the stereo field." : "Layer one to four voices."
            case 7: return oscillatorMode == 2 ? "Scatter grain pitches." : "Spread the voices’ pitches."
            case 8: return "Place the sound left or right."
            case 9:
                switch oscillatorMode {
                case 1, 2: return "Saturate the audio texture."
                case 3: return "Stretch the harmonic spacing."
                default: return "Bend the waveform’s phase."
                }
            case 10: return "Scan forward through the audio."
            case 11: return "The length of each grain."
            case 12: return "How many grains start each second."
            default: return "Change the oscillator."
            }
        }
        switch id {
        case 128: return "Remove higher frequencies."
        case 129: return "Emphasize the filter’s cutoff."
        case 130: return "Add saturation and harmonics."
        case 131: return "Blend in stereo echoes."
        case 132: return "How quickly LFO 1 cycles."
        case 133: return "The whole patch’s loudness."
        case 134: return "How quickly a note fades in."
        case 135: return "Fall from the peak to sustain."
        case 136: return "Level while you hold a note."
        case 137: return "Fade out after releasing a note."
        case 138: return "Mix in a clean sub oscillator."
        case 139: return "Mix in a little noise texture."
        case 140: return "Move all its connected controls."
        default: return "Adjust your sound."
        }
    }

    private func draw(in context: GraphicsContext, size: CGSize) {
        let width = size.width
        let height = size.height
        let center = height / 2
        let lower = height - 6
        let upper: CGFloat = 6
        let fraction = CGFloat(normalized)
        if id < 96 {
            switch id % 32 {
            case 2, 10:
                wave(in: context, size: size, cycles: 2, amplitude: 0.65, color: faint)
                let x = 6 + (width - 12) * fraction
                line(in: context, points: [CGPoint(x: x, y: 3), CGPoint(x: x, y: height - 3)], color: ink, thickness: 2)
            case 3:
                bars(in: context, size: size, amount: fraction)
            case 4, 5:
                let count = 9
                for index in 0..<count {
                    let x = CGFloat(index) * width / CGFloat(count)
                    let rect = CGRect(x: x + 1, y: 15, width: width / CGFloat(count) - 2, height: height - 18)
                    context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(faint.opacity(0.6)))
                }
                let x = 5 + (width - 10) * fraction
                let y = center - (fraction - 0.5) * 24
                context.fill(Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)), with: .color(ink))
                line(in: context, points: [CGPoint(x: width / 2, y: 4), CGPoint(x: x, y: y)], color: ink, thickness: 1.5)
            case 6:
                let count = min(4, max(1, Int(value)))
                if oscillatorMode == 2 {
                    let spread = CGFloat(count - 1) / 3 * width * 0.35
                    for grain in 0..<8 {
                        let x = width / 2 + CGFloat(sin(Double(grain) * 2.7)) * spread
                        let y = CGFloat(grain % 3) * 10 + 10
                        context.fill(Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6)), with: .color(ink.opacity(0.7)))
                    }
                    label("L", in: context, at: CGPoint(x: 5, y: center))
                    label("R", in: context, at: CGPoint(x: width - 5, y: center))
                } else {
                    for voice in 0..<count {
                        wave(in: context, size: size, cycles: 2, amplitude: 0.65,
                             phase: Double(voice) * 0.55, color: ink.opacity(1 - Double(voice) * 0.18))
                    }
                }
            case 7:
                for voice in -1...1 {
                    wave(in: context, size: size, cycles: 2 + Double(voice) * normalized * 0.45,
                         amplitude: 0.55, color: voice == 0 ? faint : ink.opacity(0.8))
                }
            case 8:
                line(in: context, points: [CGPoint(x: 12, y: center), CGPoint(x: width - 12, y: center)], color: faint, thickness: 2)
                let x = 12 + (width - 24) * fraction
                context.fill(Path(ellipseIn: CGRect(x: x - 5, y: center - 5, width: 10, height: 10)), with: .color(ink))
                label("L", in: context, at: CGPoint(x: 5, y: 8))
                label("R", in: context, at: CGPoint(x: width - 5, y: 8))
            case 9:
                if oscillatorMode == 3 {
                    for harmonic in 1...8 {
                        let h = Double(harmonic)
                        let baseX = CGFloat(h / 10) * width
                        let stretchedX = CGFloat((h + normalized * 0.015 * h * h) / 10) * width
                        let peak = center - CGFloat(16 / sqrt(h))
                        line(in: context, points: [CGPoint(x: baseX, y: lower), CGPoint(x: baseX, y: peak)], color: faint, thickness: 2)
                        line(in: context, points: [CGPoint(x: stretchedX, y: lower), CGPoint(x: stretchedX, y: peak)], color: ink, thickness: 2)
                    }
                } else {
                    wave(in: context, size: size, cycles: 2, amplitude: 0.65, color: faint)
                    wave(in: context, size: size, cycles: 2, amplitude: 0.65,
                         warp: normalized, saturated: oscillatorMode == 1 || oscillatorMode == 2, color: ink)
                }
            case 11, 12:
                let count = id % 32 == 11 ? 4 : min(12, max(1, Int(1 + normalized * 11)))
                let grainWidth = id % 32 == 11 ? max(4, width * (0.025 + normalized * 0.15)) : min(16, width / CGFloat(count + 1) * 0.55)
                for grain in 0..<count {
                    let x = width * CGFloat(grain + 1) / CGFloat(count + 1)
                    context.fill(Path(ellipseIn: CGRect(x: x - grainWidth / 2, y: center - 11, width: grainWidth, height: 22)), with: .color(ink.opacity(0.45)))
                }
            default:
                bars(in: context, size: size, amount: fraction)
            }
            return
        }
        switch id {
        case 128, 129:
            let cutoff = Double(model.value(128))
            let knee = CGFloat(log(max(20, cutoff) / 20) / log(1000)) * width * 0.75 + width * 0.1
            let resonance = CGFloat(model.value(129))
            var points: [CGPoint] = []
            for sample in 0...80 {
                let x = CGFloat(sample) / 80 * width
                let drop = max(0, (x - knee) / max(1, width - knee))
                let bump = exp(-pow((x - knee) / max(4, width * 0.04), 2)) * resonance * height * 0.23
                points.append(CGPoint(x: x, y: min(lower, center + drop * height * 0.6 - bump)))
            }
            line(in: context, points: points, color: ink, thickness: 2)
        case 130:
            wave(in: context, size: size, cycles: 2, amplitude: 0.65, color: faint)
            wave(in: context, size: size, cycles: 2, amplitude: 0.65, warp: normalized, saturated: true, color: ink)
        case 131:
            for echo in 0..<4 {
                let x = 8 + CGFloat(echo) * (width - 16) / 3
                let amount = echo == 0 ? CGFloat(1) : fraction * CGFloat(pow(0.55, Double(echo - 1)))
                line(in: context, points: [CGPoint(x: x, y: center - 15 * amount), CGPoint(x: x, y: center + 15 * amount)], color: ink.opacity(echo == 0 ? 1 : 0.75), thickness: 4)
            }
        case 132:
            let cycles = 0.75 + Double(log(max(0.05, value) / 0.05) / log(400)) * 4
            wave(in: context, size: size, cycles: cycles, amplitude: 0.75, color: ink)
        case 134...137:
            let attack = CGFloat(sqrt(max(0.001, model.value(134))))
            let decay = CGFloat(sqrt(max(0.001, model.value(135))))
            let release = CGFloat(sqrt(max(0.001, model.value(137))))
            let total = attack + decay + release + 1
            let sustain = lower - (lower - upper) * CGFloat(model.value(136))
            let points = [CGPoint(x: 4, y: lower), CGPoint(x: 4 + (width - 8) * attack / total, y: upper),
                          CGPoint(x: 4 + (width - 8) * (attack + decay) / total, y: sustain),
                          CGPoint(x: 4 + (width - 8) * (attack + decay + 1) / total, y: sustain), CGPoint(x: width - 4, y: lower)]
            line(in: context, points: points, color: faint, thickness: 1.5)
            let stage = id - 134
            if id == 136 {
                line(in: context, points: [points[2], points[3]], color: ink, thickness: 3)
            } else {
                let segment = stage == 3 ? 3 : stage
                line(in: context, points: [points[segment], points[segment + 1]], color: ink, thickness: 3)
            }
        case 139:
            var points: [CGPoint] = []
            for sample in 0...50 {
                let pseudoNoise = sin(Double(sample) * 19.17) * cos(Double(sample) * 3.71)
                points.append(CGPoint(x: width * CGFloat(sample) / 50, y: center - CGFloat(pseudoNoise) * 14 * fraction))
            }
            line(in: context, points: points, color: ink, thickness: 1.5)
        case 138:
            wave(in: context, size: size, cycles: 1, amplitude: normalized * 0.75, color: ink)
        case 140:
            let hub = CGPoint(x: width * fraction, y: center)
            for end in [CGPoint(x: width * 0.2, y: 5), CGPoint(x: width * 0.8, y: 5), CGPoint(x: width * 0.5, y: height - 5)] {
                line(in: context, points: [hub, end], color: faint, thickness: 1.5)
                context.fill(Path(ellipseIn: CGRect(x: end.x - 3, y: end.y - 3, width: 6, height: 6)), with: .color(ink))
            }
            context.fill(Path(ellipseIn: CGRect(x: hub.x - 5, y: hub.y - 5, width: 10, height: 10)), with: .color(ink))
        default:
            bars(in: context, size: size, amount: fraction)
        }
    }

    private func bars(in context: GraphicsContext, size: CGSize, amount: CGFloat) {
        for index in 0..<12 {
            let x = CGFloat(index) * size.width / 12
            let height = 10 + CGFloat(index) / 11 * 24
            let rect = CGRect(x: x + 1, y: size.height - height - 4, width: max(2, size.width / 12 - 3), height: height)
            context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(CGFloat(index) / 12 < amount ? ink : faint.opacity(0.6)))
        }
    }

    private func wave(in context: GraphicsContext, size: CGSize, cycles: Double, amplitude: Double,
                      phase: Double = 0, warp: Double = 0, saturated: Bool = false, color: Color) {
        var points: [CGPoint] = []
        for sample in 0...90 {
            let p = Double(sample) / 90 * cycles * .pi * 2 + phase
            let bent = p + sin(p) * warp * 0.9
            let raw = sin(saturated ? p : bent)
            let output = saturated ? tanh(raw * (1 + warp * 8)) : raw
            points.append(CGPoint(x: Double(sample) / 90 * size.width, y: size.height / 2 - output * amplitude * size.height * 0.42))
        }
        line(in: context, points: points, color: color, thickness: 1.6)
    }

    private func line(in context: GraphicsContext, points: [CGPoint], color: Color, thickness: CGFloat) {
        guard let first = points.first else { return }
        var path = Path()
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: thickness, lineCap: .round, lineJoin: .round))
    }

    private func label(_ text: String, in context: GraphicsContext, at point: CGPoint) {
        context.draw(Text(text).font(.system(size: 9, weight: .medium)).foregroundStyle(Color.secondary), at: point)
    }
}
