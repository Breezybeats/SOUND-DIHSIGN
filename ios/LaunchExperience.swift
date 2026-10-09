import SwiftUI
import UIKit

/// An in-app introduction; iOS launch screens themselves cannot animate.
@MainActor
struct LaunchExperienceView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    let onFinish: () -> Void
    private let artwork = UIImage(named: "CoverArtwork")

    var body: some View {
        GeometryReader { geometry in
            let artworkSize = min(280, min(geometry.size.width * 0.72, geometry.size.height * 0.43))
            VStack(spacing: 20) {
                Spacer(minLength: 12)

                LiquidCover(artwork: artwork)
                    .frame(width: artworkSize, height: artworkSize)
                    .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 36, style: .continuous)
                            .strokeBorder(.white.opacity(0.8), lineWidth: 1)
                    }
                    .shadow(color: Color(red: 0.40, green: 0.48, blue: 0.70).opacity(0.12), radius: 24, y: 12)
                    .scaleEffect(appeared ? 1 : 0.96)
                    .opacity(appeared ? 1 : 0)
                    .accessibilityHidden(true)

                VStack(spacing: 7) {
                    Text("Sound Dihsign")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.12, green: 0.14, blue: 0.19))
                    Text("A little space for big sounds.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .accessibilityElement(children: .combine)

                Spacer(minLength: 12)

                Button("Open studio", action: onFinish)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(red: 0.22, green: 0.37, blue: 0.83))
                    .padding(.horizontal, 20)
                    .frame(minHeight: 44)
                    .accessibilityHint("Skip the introduction and open the instrument")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.white.ignoresSafeArea())
        .task { @MainActor in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.55)) {
                appeared = true
            }
            do {
                try await Task.sleep(nanoseconds: reduceMotion ? 300_000_000 : 1_300_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            onFinish()
        }
    }
}

@MainActor
private struct LiquidCover: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date()

    let artwork: UIImage?

    var body: some View {
        ZStack {
            if let artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [Color(red: 1, green: 0.97, blue: 0.99), .white],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            if reduceMotion {
                liquidSurface(time: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    liquidSurface(time: timeline.date.timeIntervalSince(startedAt))
                }
            }
        }
        .clipped()
    }

    private func liquidSurface(time: Double) -> some View {
        Canvas { context, size in
            let width = size.width
            let height = size.height
            let rose = Color(red: 0.94, green: 0.58, blue: 0.72)
            let lavender = Color(red: 0.72, green: 0.61, blue: 0.96)
            let blush = Color(red: 0.93, green: 0.73, blue: 0.88)

            // Blur only the diffuse color pools, keeping the wave edges crisp.
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 24))
                let radius = width * 0.40
                let positions: [CGPoint] = [
                    CGPoint(x: width * CGFloat(0.29 + 0.12 * sin(time * 0.8)), y: height * 0.29),
                    CGPoint(x: width * 0.79, y: height * CGFloat(0.45 + 0.12 * cos(time * 0.9))),
                    CGPoint(x: width * CGFloat(0.49 + 0.15 * cos(time * 0.7)), y: height * 0.72)
                ]
                let colors = [rose, lavender, blush]
                for index in positions.indices {
                    let center = positions[index]
                    let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                    layer.fill(
                        Path(ellipseIn: rect),
                        with: .radialGradient(
                            Gradient(colors: [colors[index].opacity(0.65), colors[index].opacity(0)]),
                            center: center,
                            startRadius: 0,
                            endRadius: radius
                        )
                    )
                }
            }

            for index in 0..<3 {
                let phase = time * (0.8 + Double(index) * 0.18) + Double(index) * 1.8
                let baseline = height * (0.49 + CGFloat(index) * 0.11)
                let amplitude = height * (0.07 + CGFloat(index) * 0.008)
                var wave = Path()
                wave.move(to: CGPoint(x: 0, y: height))
                wave.addLine(to: CGPoint(x: 0, y: baseline + amplitude * CGFloat(sin(phase))))
                for step in 1...80 {
                    let fraction = Double(step) / 80
                    let y = baseline + amplitude * CGFloat(sin(fraction * .pi * 2 + phase))
                        + amplitude * 0.35 * CGFloat(sin(fraction * .pi * 3 - phase * 0.6))
                    wave.addLine(to: CGPoint(x: width * CGFloat(fraction), y: y))
                }
                wave.addLine(to: CGPoint(x: width, y: height))
                wave.closeSubpath()

                let tint = [lavender, rose, blush][index]
                context.fill(
                    wave,
                    with: .linearGradient(
                        Gradient(colors: [tint.opacity(0.38), tint.opacity(0.08)]),
                        startPoint: CGPoint(x: 0, y: baseline),
                        endPoint: CGPoint(x: width, y: height)
                    )
                )
            }
        }
        .opacity(artwork == nil ? 1 : 0.38)
    }
}
