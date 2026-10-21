import XCTest
@testable import MovieRouletteTuesday
import MRTCore

final class WheelMathTests: XCTestCase {
    private let six = 6

    func testZeroRotationLandsOnSegmentZero() {
        XCTAssertEqual(WheelMath.segmentIndex(forRotation: 0, segmentCount: six), 0)
    }

    func testClockwiseRotationBringsEarlierSegmentsUnderPointer() {
        // Rotating clockwise moves segment 5 (the one left of 12 o'clock) under the pointer first.
        XCTAssertEqual(WheelMath.segmentIndex(forRotation: 30, segmentCount: six), 5)
        XCTAssertEqual(WheelMath.segmentIndex(forRotation: 90, segmentCount: six), 4)
        XCTAssertEqual(WheelMath.segmentIndex(forRotation: 330, segmentCount: six), 0)
    }

    func testBoundaryBelongsToSegmentStartingThere() {
        for k in 0..<six {
            let boundary = -Double(k) * 60 // puts the start of segment k under the pointer
            XCTAssertEqual(WheelMath.segmentIndex(forRotation: boundary, segmentCount: six), k, "on boundary \(k)")
            // A hair more clockwise rotation -> the previous segment's end is under the pointer.
            XCTAssertEqual(
                WheelMath.segmentIndex(forRotation: boundary + 1e-9, segmentCount: six),
                (k + six - 1) % six, "just before boundary \(k)"
            )
            XCTAssertEqual(WheelMath.segmentIndex(forRotation: boundary - 1e-9, segmentCount: six), k, "just after boundary \(k)")
        }
    }

    func testPositiveBoundariesMatchNegativeOnes() {
        // +300 and -60 are the same wheel position.
        XCTAssertEqual(WheelMath.segmentIndex(forRotation: 300, segmentCount: six), 1)
        XCTAssertEqual(WheelMath.segmentIndex(forRotation: 360, segmentCount: six), 0)
        XCTAssertEqual(WheelMath.segmentIndex(forRotation: 60, segmentCount: six), 5)
    }

    func testFullTurnsDoNotChangeResult() {
        let rotations: [Double] = [0, 12.5, 59.999, 60, 137, 299.5, 359.99]
        for rotation in rotations {
            let base = WheelMath.segmentIndex(forRotation: rotation, segmentCount: six)
            for turns in 1...20 {
                XCTAssertEqual(WheelMath.segmentIndex(forRotation: rotation + Double(turns) * 360, segmentCount: six), base)
                XCTAssertEqual(WheelMath.segmentIndex(forRotation: rotation - Double(turns) * 360, segmentCount: six), base)
            }
        }
    }

    func testNegativeAngles() {
        XCTAssertEqual(WheelMath.segmentIndex(forRotation: -30, segmentCount: six), 0)
        XCTAssertEqual(WheelMath.segmentIndex(forRotation: -90, segmentCount: six), 1)
        XCTAssertEqual(WheelMath.segmentIndex(forRotation: -359, segmentCount: six), 5)
        XCTAssertEqual(WheelMath.segmentIndex(forRotation: -390, segmentCount: six), 0)
        XCTAssertEqual(WheelMath.segmentIndex(forRotation: -0.0, segmentCount: six), 0)
    }

    func testHugeAngles() {
        // 3.6e12 is an exact multiple of 360 and exactly representable.
        XCTAssertEqual(WheelMath.segmentIndex(forRotation: 3.6e12 + 90, segmentCount: six), 4)
        XCTAssertEqual(WheelMath.segmentIndex(forRotation: -3.6e12 - 90, segmentCount: six), 1)
        for value in [Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude, 1e300, -1e300] {
            XCTAssertTrue((0..<six).contains(WheelMath.segmentIndex(forRotation: value, segmentCount: six)))
        }
    }

    func testNonFiniteRotationFallsBackToZero() {
        XCTAssertEqual(WheelMath.segmentIndex(forRotation: .nan, segmentCount: six), 0)
        XCTAssertEqual(WheelMath.segmentIndex(forRotation: .infinity, segmentCount: six), 0)
        XCTAssertEqual(WheelMath.segmentIndex(forRotation: -.infinity, segmentCount: six), 0)
    }

    func testPointerAngleIsAlwaysNormalized() {
        let samples: [Double] = [0, -0.0, 360, -360, 720.25, -1e-15, 1e-15, -1e-300, 1e15 + 0.5, -123456.789]
        for value in samples {
            let angle = WheelMath.pointerAngle(forRotation: value)
            XCTAssertGreaterThanOrEqual(angle, 0, "\(value)")
            XCTAssertLessThan(angle, 360, "\(value)")
            XCTAssertEqual(angle.sign, .plus, "\(value)")
        }
        XCTAssertEqual(WheelMath.pointerAngle(forRotation: 90), 270)
        XCTAssertEqual(WheelMath.pointerAngle(forRotation: -90), 90)
    }

    func testEverySegmentIsReachableForVariousCounts() {
        for count in 1...12 {
            let sweep = 360 / Double(count)
            for k in 0..<count {
                let rotationForMidpoint = -(Double(k) + 0.5) * sweep
                XCTAssertEqual(WheelMath.segmentIndex(forRotation: rotationForMidpoint, segmentCount: count), k)
            }
            // A fine sweep over one turn hits every segment roughly equally.
            var hits = [Int](repeating: 0, count: count)
            for step in 0..<3600 {
                hits[WheelMath.segmentIndex(forRotation: Double(step) * 0.1, segmentCount: count)] += 1
            }
            XCTAssertFalse(hits.contains(0), "count \(count): \(hits)")
            let expected = 3600 / count
            XCTAssertTrue(hits.allSatisfy { abs($0 - expected) <= 1 }, "count \(count): \(hits)")
        }
    }

    func testIndexAlwaysInRangeForRandomRotations() {
        var rng = SeededRandomNumberGenerator(seed: 42)
        for _ in 0..<10_000 {
            let rotation = Double.random(in: -1e9...1e9, using: &rng)
            let count = Int.random(in: 1...16, using: &rng)
            XCTAssertTrue((0..<count).contains(WheelMath.segmentIndex(forRotation: rotation, segmentCount: count)))
        }
    }

    func testTargetRotationAccumulates() {
        XCTAssertEqual(WheelMath.targetRotation(from: 1000, fullTurns: 6, extraDegrees: 45), 1000 + 2160 + 45)
    }
}

final class WheelGeometryTests: XCTestCase {
    func testUniformGeometryMatchesStaticMath() {
        var rng = SeededRandomNumberGenerator(seed: 7)
        for count in 1...10 {
            let geometry = WheelGeometry(segmentCount: count)
            XCTAssertTrue(geometry.isUniform)
            XCTAssertEqual(geometry.segments.first?.startAngle, 0)
            XCTAssertEqual(geometry.segments.last?.endAngle, 360)
            for _ in 0..<500 {
                let rotation = Double.random(in: -100_000...100_000, using: &rng)
                XCTAssertEqual(geometry.segmentIndex(forRotation: rotation),
                               WheelMath.segmentIndex(forRotation: rotation, segmentCount: count))
            }
        }
    }

    func testWeightedSegmentsAreProportional() {
        let geometry = WheelGeometry(weights: [1, 2, 1])
        XCTAssertFalse(geometry.isUniform)
        XCTAssertEqual(geometry.segments.map(\.sweep), [90, 180, 90])
        XCTAssertEqual(geometry.segmentIndex(forRotation: 0), 0)
        XCTAssertEqual(geometry.segmentIndex(forRotation: -89.9), 0)
        XCTAssertEqual(geometry.segmentIndex(forRotation: -90), 1)   // boundary -> starting segment
        XCTAssertEqual(geometry.segmentIndex(forRotation: -269.9), 1)
        XCTAssertEqual(geometry.segmentIndex(forRotation: -270), 2)
        XCTAssertEqual(geometry.segmentIndex(forRotation: 45), 2)    // clockwise 45 -> pointer at 315
        XCTAssertEqual(geometry.segmentIndex(forRotation: 360 * 9 - 100), 1)
    }

    func testInvalidWeightsCountAsOne() {
        let geometry = WheelGeometry(weights: [nil, 0, -3, .nan, 1])
        XCTAssertTrue(geometry.isUniform)
        XCTAssertEqual(geometry.count, 5)
    }

    func testRandomTargetAlwaysSpinsForwardSeveralTurnsAndAvoidsEdges() {
        var rng = SeededRandomNumberGenerator(seed: 2026)
        for geometry in [WheelGeometry(segmentCount: 6), WheelGeometry(weights: [1, 3, 0.5, 2])] {
            var current = 123.0
            for _ in 0..<2_000 {
                let target = geometry.randomTargetRotation(from: current, edgePadding: 3, using: &rng)
                let delta = target - current
                XCTAssertGreaterThanOrEqual(delta, 5 * 360 - 3)
                XCTAssertLessThan(delta, 9 * 360)
                let angle = WheelMath.pointerAngle(forRotation: target)
                let segment = geometry.segments[geometry.segmentIndex(forRotation: target)]
                let padding = min(3, segment.sweep / 4)
                XCTAssertGreaterThanOrEqual(angle - segment.startAngle, padding - 1e-6)
                XCTAssertGreaterThanOrEqual(segment.endAngle - angle, padding - 1e-6)
                current = target // accumulate like the app does
            }
        }
    }

    func testRandomTargetIsDeterministicAndFair() {
        var a = SeededRandomNumberGenerator(seed: 99)
        var b = SeededRandomNumberGenerator(seed: 99)
        let geometry = WheelGeometry(segmentCount: 6)
        for _ in 0..<50 {
            XCTAssertEqual(geometry.randomTargetRotation(from: 0, using: &a),
                           geometry.randomTargetRotation(from: 0, using: &b))
        }
        var rng = SeededRandomNumberGenerator(seed: 1)
        var hits = [Int](repeating: 0, count: 6)
        var current = 0.0
        for _ in 0..<6_000 {
            current = geometry.randomTargetRotation(from: current, using: &rng)
            hits[geometry.segmentIndex(forRotation: current)] += 1
        }
        XCTAssertTrue(hits.allSatisfy { (850...1150).contains($0) }, "\(hits)")
    }
}
