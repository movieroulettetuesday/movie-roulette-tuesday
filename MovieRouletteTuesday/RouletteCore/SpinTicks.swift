import Foundation

/// A CSS/SwiftUI-style cubic Bézier timing curve from (0,0) to (1,1).
/// `Animation.timingCurve(c1x, c1y, c2x, c2y, duration:)` uses the same definition.
public struct TimingCurve: Equatable, Sendable {
    public var c1x: Double, c1y: Double, c2x: Double, c2y: Double

    public init(_ c1x: Double, _ c1y: Double, _ c2x: Double, _ c2y: Double) {
        self.c1x = c1x; self.c1y = c1y; self.c2x = c2x; self.c2y = c2y
    }

    /// The roulette spin: fast start, long slow stop.
    public static let spin = TimingCurve(0.12, 0.8, 0.2, 1)
    /// SwiftUI/Core Animation `.easeOut`.
    public static let easeOut = TimingCurve(0, 0, 0.58, 1)
    public static let linear = TimingCurve(0, 0, 1, 1)

    private static func bezier(_ s: Double, _ a: Double, _ b: Double) -> Double {
        let u = 1 - s
        return 3 * u * u * s * a + 3 * u * s * s * b + s * s * s
    }

    public func x(atParameter s: Double) -> Double { Self.bezier(s, c1x, c2x) }
    public func y(atParameter s: Double) -> Double { Self.bezier(s, c1y, c2y) }

    /// Animation progress (0...1) at time fraction `t` (0...1).
    public func progress(atTimeFraction t: Double) -> Double {
        let t = min(max(t, 0), 1)
        return y(atParameter: solve(target: t, component: x(atParameter:)))
    }

    /// Time fraction (0...1) at which the animation reaches `progress` (0...1).
    /// Requires a monotonic curve (control y values in 0...1), which all spin curves are.
    public func timeFraction(atProgress progress: Double) -> Double {
        let p = min(max(progress, 0), 1)
        return x(atParameter: solve(target: p, component: y(atParameter:)))
    }

    /// Bisection on the Bézier parameter; components are monotonic for our curves.
    private func solve(target: Double, component: (Double) -> Double) -> Double {
        var lo = 0.0, hi = 1.0
        for _ in 0..<60 {
            let mid = (lo + hi) / 2
            if component(mid) < target { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }
}

/// When the pointer passes each slice boundary during a spin, so the app can
/// schedule tick sounds/haptics that line up with what's on screen.
public enum SpinTicks {
    /// Rotations (absolute, degrees) in `(from, to]` at which a slice boundary is
    /// under the 12 o'clock pointer, in increasing order. Rotating clockwise by R
    /// puts wheel angle `(-R) mod 360` under the pointer, so boundary `b` is
    /// crossed whenever `R ≡ -b (mod 360)`.
    public static func boundaryRotations(from start: Double, to end: Double, geometry: WheelGeometry) -> [Double] {
        guard start.isFinite, end.isFinite, end > start, geometry.count > 1 else { return [] }
        var result: [Double] = []
        for segment in geometry.segments {
            let base = -segment.startAngle // any rotation ≡ -b (mod 360)
            // Smallest k with base + 360k > start.
            var k = ((start - base) / WheelMath.fullTurn).rounded(.down) + 1
            var r = base + k * WheelMath.fullTurn
            while r <= start { k += 1; r = base + k * WheelMath.fullTurn }
            while r <= end {
                result.append(r)
                k += 1
                r = base + k * WheelMath.fullTurn
            }
        }
        return result.sorted()
    }

    /// Seconds after the spin starts at which each boundary crossing happens,
    /// for an animation from `start` to `end` rotation following `curve` over
    /// `duration`. Ticks closer than `minInterval` to the previous kept tick are
    /// dropped (the start of a spin is far too fast to tick every slice), and a
    /// crossing that coincides with the very end of the spin is dropped as well.
    public static func tickTimes(
        from start: Double,
        to end: Double,
        geometry: WheelGeometry,
        curve: TimingCurve,
        duration: Double,
        minInterval: Double = 0.04
    ) -> [Double] {
        guard duration > 0, duration.isFinite else { return [] }
        let span = end - start
        var times: [Double] = []
        for rotation in boundaryRotations(from: start, to: end, geometry: geometry) {
            let progress = (rotation - start) / span
            let time = curve.timeFraction(atProgress: progress) * duration
            guard time < duration - 1e-6 else { continue }
            if let last = times.last, time - last < minInterval { continue }
            times.append(time)
        }
        return times
    }

    /// Drops times closer than `minInterval` to the previous kept time
    /// (ascending input), e.g. haptics for very close crossings.
    public static func thinned(_ times: [Double], minInterval: Double) -> [Double] {
        var kept: [Double] = []
        for time in times {
            if let last = kept.last, time - last < minInterval { continue }
            kept.append(time)
        }
        return kept
    }
}
