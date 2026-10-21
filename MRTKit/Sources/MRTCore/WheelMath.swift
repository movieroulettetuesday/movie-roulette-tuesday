import Foundation

/// Pure geometry for the wheel.
///
/// Conventions (shared by the drawing code and the winner math):
/// - Angles are degrees, measured clockwise from 12 o'clock.
/// - Segment 0 starts at 12 o'clock; segments continue clockwise.
/// - The wheel rotates clockwise by `rotation` degrees (SwiftUI's
///   `.rotationEffect(.degrees(rotation))` with a positive value).
/// - The pointer is fixed at 12 o'clock.
/// - A pointer exactly on a boundary belongs to the segment that *starts* there.
public enum WheelMath {
    public static let fullTurn: Double = 360

    /// The wheel-local angle in `[0, 360)` sitting under the top pointer after
    /// the wheel has rotated clockwise by `degrees`. Handles negative and huge
    /// values; non-finite input returns 0.
    public static func pointerAngle(forRotation degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        // Rotating clockwise by R moves the wheel point at local angle -R to the top.
        // truncatingRemainder (fmod) is exact, so huge rotations don't lose accuracy.
        var angle = (-degrees).truncatingRemainder(dividingBy: fullTurn)
        if angle < 0 { angle += fullTurn }
        // A tiny negative remainder + 360 can round up to exactly 360.
        if angle >= fullTurn { angle -= fullTurn }
        return angle == 0 ? 0 : angle // normalizes -0.0
    }

    /// Index of the equal-size segment under the top pointer.
    public static func segmentIndex(forRotation degrees: Double, segmentCount: Int) -> Int {
        // Defensive: never trap at runtime. An empty wheel or a non-finite
        // angle (shouldn't happen) both resolve to the first segment.
        guard segmentCount > 0, degrees.isFinite else { return 0 }
        let sweep = fullTurn / Double(segmentCount)
        let raw = Int((pointerAngle(forRotation: degrees) / sweep).rounded(.down))
        return min(max(raw, 0), segmentCount - 1)
    }

    /// `current + fullTurns * 360 + extraDegrees`. Rotation only ever accumulates.
    public static func targetRotation(from current: Double, fullTurns: Int, extraDegrees: Double) -> Double {
        current + Double(fullTurns) * fullTurn + extraDegrees
    }
}

/// Segment layout for a wheel whose slices may have different sizes
/// (`RouletteCategory.weight`). Drawing and winner detection both use this
/// one value, so what you see is exactly what is computed.
public struct WheelGeometry: Equatable, Sendable {
    public struct Segment: Equatable, Identifiable, Sendable {
        public let index: Int
        /// Inclusive start, degrees clockwise from 12 o'clock.
        public let startAngle: Double
        /// Exclusive end. The last segment always ends at exactly 360.
        public let endAngle: Double

        public var id: Int { index }
        public var sweep: Double { endAngle - startAngle }
        public var midAngle: Double { startAngle + sweep / 2 }
    }

    public let segments: [Segment]
    /// All slices equal: winner math delegates to `WheelMath.segmentIndex`.
    public let isUniform: Bool

    /// `nil`, zero, negative or non-finite weights count as 1. An empty list
    /// is treated as a single segment (callers guard against an empty catalog,
    /// but a geometry must never be able to crash the app).
    public init(weights: [Double?]) {
        let input: [Double?] = weights.isEmpty ? [1] : weights
        let sanitized = input.map { w -> Double in
            guard let w, w.isFinite, w > 0 else { return 1 }
            return w
        }
        let uniform = Set(sanitized).count == 1
        let total = sanitized.reduce(0, +)
        var segments: [Segment] = []
        var cumulative = 0.0
        for (index, weight) in sanitized.enumerated() {
            let start: Double
            let end: Double
            if uniform {
                let sweep = WheelMath.fullTurn / Double(sanitized.count)
                start = Double(index) * sweep
                end = index == sanitized.count - 1 ? WheelMath.fullTurn : Double(index + 1) * sweep
            } else {
                start = WheelMath.fullTurn * cumulative / total
                cumulative += weight
                end = index == sanitized.count - 1 ? WheelMath.fullTurn : WheelMath.fullTurn * cumulative / total
            }
            segments.append(Segment(index: index, startAngle: start, endAngle: end))
        }
        self.segments = segments
        self.isUniform = uniform
    }

    public init(segmentCount: Int) {
        self.init(weights: Array(repeating: 1, count: max(segmentCount, 0)))
    }

    public init(categories: [RouletteCategory]) {
        self.init(weights: categories.map(\.weight))
    }

    public var count: Int { segments.count }

    /// Index of the segment under the top pointer for a given total rotation.
    public func segmentIndex(forRotation degrees: Double) -> Int {
        if isUniform {
            return WheelMath.segmentIndex(forRotation: degrees, segmentCount: segments.count)
        }
        guard degrees.isFinite else { return 0 }
        let angle = WheelMath.pointerAngle(forRotation: degrees)
        return segments.last(where: { angle >= $0.startAngle })?.index ?? 0
    }

    /// A random clockwise spin target: `current` + `fullTurns` whole turns + a
    /// random extra angle. The landing point is then nudged (within the same
    /// segment, so odds are unchanged) to stay `edgePadding` degrees away from a
    /// boundary, so the pointer never visibly sits on a dividing line.
    public func randomTargetRotation<G: RandomNumberGenerator>(
        from current: Double,
        fullTurns: ClosedRange<Int> = 5...8,
        edgePadding: Double = 3,
        using rng: inout G
    ) -> Double {
        let turns = Int.random(in: fullTurns, using: &rng)
        let extra = Double.random(in: 0..<WheelMath.fullTurn, using: &rng)
        var target = WheelMath.targetRotation(from: current, fullTurns: turns, extraDegrees: extra)

        let angle = WheelMath.pointerAngle(forRotation: target)
        let index = segmentIndex(forRotation: target)
        guard segments.indices.contains(index) else { return target }
        let segment = segments[index]
        let padding = min(max(edgePadding, 0), segment.sweep / 4)
        let clamped = min(max(angle, segment.startAngle + padding), segment.endAngle - padding)
        // The pointer angle grows as rotation shrinks, so subtract the correction.
        target -= clamped - angle
        return target
    }
}
