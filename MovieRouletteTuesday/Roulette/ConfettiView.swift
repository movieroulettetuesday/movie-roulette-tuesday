import SwiftUI
import MRTCore

/// Lightweight one-shot confetti: ~60 rectangles drawn in a Canvas with
/// positions computed analytically from elapsed time (no per-particle state
/// updates). Stops itself after `duration`; skipped entirely with Reduce Motion.
struct ConfettiView: View {
    var particleCount = 60
    var duration: TimeInterval = 2.8
    var colors: [Color] = [.red, .orange, .yellow, .green, .mint, .blue, .purple, .pink]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var particles: [ConfettiParticle] = []
    @State private var startDate = Date.now
    @State private var isFinished = false
    /// Piece size multiplier; > 1 on wide iPad sheets.
    @State private var pieceScale: CGFloat = 1

    var body: some View {
        Group {
            if reduceMotion || isFinished {
                Color.clear
            } else {
                GeometryReader { proxy in
                    TimelineView(.animation) { timeline in
                        Canvas { context, size in
                            let elapsed = timeline.date.timeIntervalSince(startDate)
                            for particle in particles {
                                particle.draw(
                                    in: context, canvasSize: size, elapsed: elapsed,
                                    duration: duration, scale: pieceScale
                                )
                            }
                        }
                    }
                    .task { await run(width: proxy.size.width) }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// One burst; density and piece size scale with the width (iPhone unchanged).
    private func run(width: CGFloat) async {
        let count = ConfettiScale.particleCount(forWidth: Double(width), base: particleCount)
        pieceScale = CGFloat(ConfettiScale.pieceScale(forWidth: Double(width)))
        particles = (0..<count).map { _ in ConfettiParticle.random(colors: colors) }
        startDate = .now
        try? await Task.sleep(for: .seconds(duration))
        isFinished = true
        particles = []  // release particle state once the burst is over
    }
}

private struct ConfettiParticle {
    var startX: CGFloat      // fraction of canvas width
    var velocityX: CGFloat   // pt/s
    var velocityY: CGFloat   // pt/s, positive = down
    var delay: CGFloat       // s
    var spin: CGFloat        // deg/s
    var flip: CGFloat        // rad/s, cheap 3D tumble via x-scale
    var wobblePhase: CGFloat
    var size: CGSize
    var color: Color

    static func random(colors: [Color]) -> ConfettiParticle {
        ConfettiParticle(
            startX: .random(in: 0.05...0.95),
            velocityX: .random(in: -40...40),
            velocityY: .random(in: 20...120),
            delay: .random(in: 0...0.35),
            spin: .random(in: -360...360),
            flip: .random(in: 3...9),
            wobblePhase: .random(in: 0...(2 * .pi)),
            size: CGSize(width: CGFloat.random(in: 6...10), height: CGFloat.random(in: 3...6)),
            color: colors.randomElement() ?? .pink
        )
    }

    func draw(in context: GraphicsContext, canvasSize: CGSize, elapsed: TimeInterval, duration: TimeInterval, scale: CGFloat = 1) {
        let t = CGFloat(elapsed) - delay
        guard t > 0 else { return }
        let gravity: CGFloat = 300
        let x = startX * canvasSize.width + velocityX * t + sin(t * 6 + wobblePhase) * 8
        let y = -12 + velocityY * t + 0.5 * gravity * t * t
        guard y < canvasSize.height + 20 else { return }

        let fadeStart = duration * 0.65
        let opacity = elapsed < fadeStart ? 1 : max(0, 1 - (elapsed - fadeStart) / max(duration - fadeStart, 0.001))

        var context = context
        context.opacity = opacity
        context.translateBy(x: x, y: y)
        context.rotate(by: .degrees(Double(spin * t)))
        context.scaleBy(x: cos(flip * t) * scale, y: scale)
        let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
        context.fill(Path(rect), with: .color(color))
    }
}

#Preview {
    ConfettiView()
}
