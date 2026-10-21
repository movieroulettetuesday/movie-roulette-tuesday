import XCTest
@testable import MovieRouletteTuesday
import MRTCore

final class SpinTicksTests: XCTestCase {
    func testCurveEndpointsAndInverse() {
        let c = TimingCurve.spin
        XCTAssertEqual(c.progress(atTimeFraction: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(c.progress(atTimeFraction: 1), 1, accuracy: 1e-9)
        for p in stride(from: 0.05, to: 1.0, by: 0.05) {
            XCTAssertEqual(c.progress(atTimeFraction: c.timeFraction(atProgress: p)), p, accuracy: 1e-6)
        }
        // Ease-out: well past halfway in rotation at half time.
        XCTAssertGreaterThan(c.progress(atTimeFraction: 0.5), 0.85)
        XCTAssertEqual(TimingCurve.linear.timeFraction(atProgress: 0.3), 0.3, accuracy: 1e-9)
    }

    func testBoundaryRotationsCountAndValues() {
        let g = WheelGeometry(segmentCount: 10)
        // Exactly 3 turns: every boundary crossed 3 times.
        let r = SpinTicks.boundaryRotations(from: 0, to: 1080, geometry: g)
        XCTAssertEqual(r.count, 30)
        XCTAssertEqual(r.first!, 36, accuracy: 1e-9)
        XCTAssertEqual(r.last!, 1080, accuracy: 1e-9)
        XCTAssertEqual(r, r.sorted())
        // Starting mid-segment, non-zero start.
        let s = SpinTicks.boundaryRotations(from: 370, to: 370 + 100, geometry: g)
        XCTAssertEqual(s, [396, 432, 468])
        XCTAssertTrue(SpinTicks.boundaryRotations(from: 10, to: 10, geometry: g).isEmpty)
        XCTAssertTrue(SpinTicks.boundaryRotations(from: 0, to: 720, geometry: WheelGeometry(segmentCount: 1)).isEmpty)
    }

    func testEachCrossingChangesTheSegmentUnderThePointer() {
        let g = WheelGeometry(weights: [1, 2, 3, 1])
        for r in SpinTicks.boundaryRotations(from: 12.3, to: 12.3 + 720, geometry: g) {
            XCTAssertNotEqual(g.segmentIndex(forRotation: r - 0.01), g.segmentIndex(forRotation: r + 0.01))
        }
    }

    func testLinearCurveTicksAreEvenlySpaced() {
        let g = WheelGeometry(segmentCount: 4)
        let t = SpinTicks.tickTimes(from: 0, to: 360 * 2 + 45, geometry: g, curve: .linear, duration: 7.65, minInterval: 0)
        XCTAssertEqual(t.count, 8)
        XCTAssertEqual(t[0], 0.9, accuracy: 1e-6) // 90° of 765° in 7.65 s
        for (a, b) in zip(t, t.dropFirst()) { XCTAssertEqual(b - a, 0.9, accuracy: 1e-6) }
    }

    func testSpinCurveTicksSlowDownAndRespectMinInterval() {
        let g = WheelGeometry(segmentCount: 10)
        let times = SpinTicks.tickTimes(from: 100, to: 100 + 360 * 6 + 200, geometry: g, curve: .spin, duration: 4, minInterval: 0.04)
        XCTAssertFalse(times.isEmpty)
        XCTAssertEqual(times, times.sorted())
        XCTAssertTrue(times.allSatisfy { $0 >= 0 && $0 < 4 })
        for (a, b) in zip(times, times.dropFirst()) { XCTAssertGreaterThanOrEqual(b - a, 0.04 - 1e-9) }
        // Gaps grow toward the end (ease-out).
        let gaps = zip(times, times.dropFirst()).map { $1 - $0 }
        XCTAssertGreaterThan(gaps.last!, gaps.first! * 3)
        // Without thinning, one tick per crossing.
        let all = SpinTicks.tickTimes(from: 100, to: 100 + 360 * 6 + 200, geometry: g, curve: .spin, duration: 4, minInterval: 0)
        XCTAssertEqual(all.count, SpinTicks.boundaryRotations(from: 100, to: 100 + 360 * 6 + 200, geometry: g).count)
        XCTAssertGreaterThan(all.count, times.count)
    }

    func testThinnedKeepsSpacing() {
        XCTAssertEqual(SpinTicks.thinned([0.1, 0.12, 0.2, 0.24, 0.3], minInterval: 0.045), [0.1, 0.2, 0.3])
        XCTAssertEqual(SpinTicks.thinned([], minInterval: 0.045), [])
    }

    /// Haptics for the clip-timed spin: one per crossing, on the clicks, the
    /// last one before the wheel stops.
    func testClipTimedHapticsFollowTheCrossings() {
        let g = WheelGeometry(weights: [1, 2, 1, 1, 3, 1, 1, 1, 2, 1])
        let m = SpinMotion.plan(from: 30, to: 30 + 360 * 6 + 77, geometry: g)
        let haptics = SpinTicks.thinned(m.crossingTimes, minInterval: 0.045)
        XCTAssertGreaterThan(haptics.count, 50)
        XCTAssertLessThan(haptics.last!, m.duration)
        for (a, b) in zip(haptics, haptics.dropFirst()) { XCTAssertGreaterThanOrEqual(b - a, 0.045 - 1e-12) }
        XCTAssertTrue(Set(haptics).isSubset(of: Set(m.crossingTimes)))
    }
}
