import XCTest
@testable import MovieRouletteTuesday

/// The spin is timed to Walter's recording: speed follows the click rate,
/// crossings land on clicks, the wheel stops on the final thunk, and where it
/// lands is still decided only by the (uniform) random target.
final class SpinMotionTests: XCTestCase {
    func testTrackDataIsSane() {
        let t = SpinSoundTrack.self
        XCTAssertGreaterThan(t.onsets.count, 250)
        XCTAssertEqual(t.onsets, t.onsets.sorted())
        XCTAssertLessThan(t.onsets.last!, t.stopTime)
        XCTAssertGreaterThan(t.onsets.first!, 0)
        XCTAssertEqual(t.spinDuration, t.stopTime + t.brakeDuration, accuracy: 1e-12)
        XCTAssertLessThanOrEqual(t.spinDuration, t.clipDuration)   // the clip outlasts the motion
        XCTAssertEqual(t.spinDuration, 6.294, accuracy: 0.01)
        // Ratchet: ~53 -> ~44 clicks/s.
        XCTAssertEqual(1 / (t.periodIntercept + t.periodSlope * 0.3), 53, accuracy: 2)
        XCTAssertEqual(1 / (t.periodIntercept + t.periodSlope * t.stopTime), 44, accuracy: 2)
    }

    func testBaseCurveEndpointsMonotonicAndInverse() {
        XCTAssertEqual(SpinMotion.baseProgress(at: 0), 0)
        XCTAssertEqual(SpinMotion.baseProgress(at: SpinSoundTrack.spinDuration), 1, accuracy: 1e-9)
        var last = -1.0
        for t in stride(from: 0.0, through: SpinSoundTrack.spinDuration, by: 0.005) {
            let p = SpinMotion.baseProgress(at: t)
            XCTAssertGreaterThanOrEqual(p, last); last = p
        }
        for p in stride(from: 0.02, to: 1.0, by: 0.02) {
            XCTAssertEqual(SpinMotion.baseProgress(at: SpinMotion.baseTime(atProgress: p)), p, accuracy: 1e-6)
        }
        // Speed follows the click rate: the cruise slows ~15% from 1 s to just before the stop...
        let v = { (t: Double) in (SpinMotion.baseProgress(at: t + 0.01) - SpinMotion.baseProgress(at: t - 0.01)) / 0.02 }
        XCTAssertEqual(v(6.1) / v(1.0), (SpinSoundTrack.periodIntercept + SpinSoundTrack.periodSlope * 1.0)
                                        / (SpinSoundTrack.periodIntercept + SpinSoundTrack.periodSlope * 6.1), accuracy: 0.02)
        // ...it winds up from slow, and is at rest after the brake.
        XCTAssertLessThan(v(0.02), v(1.0) * 0.35)
        XCTAssertLessThan(v(SpinSoundTrack.spinDuration - 0.005), v(1.0) * 0.08)
    }

    func testCrossingsLandOnClicksAndHitTheirBoundariesExactly() {
        var rng = SeededRandomNumberGenerator(seed: 2026)
        let g = WheelGeometry(segmentCount: 10)
        var snapped = 0, total = 0, maxShift = 0.0, shifts: [Double] = []
        var start = 0.0
        for _ in 0..<300 {
            let end = g.randomTargetRotation(from: start, fullTurns: 5...8, using: &rng)
            let m = SpinMotion.plan(from: start, to: end, geometry: g)
            let boundaries = SpinTicks.boundaryRotations(from: start, to: end, geometry: g)
                .filter { $0 < end - 1e-9 }
            XCTAssertEqual(m.crossingTimes.count, boundaries.count, "one haptic per crossing")
            XCTAssertEqual(m.crossingTimes, m.crossingTimes.sorted())
            for (time, rotation) in zip(m.crossingTimes, boundaries) {
                // The wheel is exactly on the boundary at the crossing time.
                XCTAssertEqual(start + (end - start) * m.progress(at: time), rotation, accuracy: 1e-6)
                total += 1
                if time < SpinSoundTrack.stopTime {
                    // ...and that instant is a click onset in the recording.
                    let onClick = SpinSoundTrack.onsets.contains { abs($0 - time) < 1e-9 }
                    if onClick { snapped += 1 }
                }
            }
            for o in m.snapOffsets { maxShift = max(maxShift, abs(o)); shifts.append(abs(o)) }
            // Lands exactly on the target: timing never changes the outcome.
            XCTAssertEqual(m.progress(at: m.duration), 1)
            XCTAssertEqual(m.progress(at: m.duration + 1), 1)
            start = end
        }
        shifts.sort()
        print(String(format: "MRT-SPIN-ALIGN crossings=%d onClick=%d (%.1f%%) shift median=%.1f ms p95=%.1f ms max=%.1f ms",
                     total, snapped, 100 * Double(snapped) / Double(total),
                     1000 * shifts[shifts.count / 2], 1000 * shifts[Int(Double(shifts.count) * 0.95)], 1000 * maxShift))
        XCTAssertGreaterThan(Double(snapped) / Double(total), 0.95, "nearly every crossing is on a click")
        XCTAssertLessThanOrEqual(maxShift, SpinMotion.maxSnap + 1e-9)
    }

    func testProgressIsMonotonicAndSmooth() {
        var rng = SeededRandomNumberGenerator(seed: 7)
        let g = WheelGeometry(weights: [1, 2, 1, 1, 3, 1, 1, 1, 2, 1])
        var maxJump = 0.0
        defer { print(String(format: "MRT-SPIN-SMOOTH worst frame-to-frame speed change %.1f%%", 100 * maxJump)) }
        for _ in 0..<40 {
            let end = g.randomTargetRotation(from: 123, fullTurns: 5...8, using: &rng)
            let m = SpinMotion.plan(from: 123, to: end, geometry: g)
            var last = m.progress(at: 0.6 - 1.0 / 120), lastV = 0.0, worstJump = 0.0
            for t in stride(from: 0.6, through: 6.1, by: 1.0 / 120) {
                let p = m.progress(at: t)
                XCTAssertGreaterThanOrEqual(p, last - 1e-12)
                let v = p - last
                if lastV > 0 { worstJump = max(worstJump, abs(v / lastV - 1)) }
                last = p; lastV = v
            }
            // Snapping only nudges the speed (like the flapper catching a peg; no stall or jump).
            XCTAssertLessThan(worstJump, 0.3)
            maxJump = max(maxJump, worstJump)
        }
    }

    func testLandingStaysUniform() {
        // The target (and so the landing slice) comes from randomTargetRotation as
        // before; the motion plan always ends exactly on it.
        var rng = SeededRandomNumberGenerator(seed: 99)
        let g = WheelGeometry(segmentCount: 10)
        var counts = [Int](repeating: 0, count: 10)
        var start = 0.0
        let n = 20_000
        for _ in 0..<n {
            let end = g.randomTargetRotation(from: start, fullTurns: 5...8, using: &rng)
            let m = SpinMotion.plan(from: start, to: end, geometry: g, onsets: [])
            let landed = start + (end - start) * m.progress(at: m.duration)
            XCTAssertEqual(landed, end)
            counts[g.segmentIndex(forRotation: landed)] += 1
            start = end
        }
        let expected = Double(n) / 10
        let chi2 = counts.reduce(0.0) { $0 + pow(Double($1) - expected, 2) / expected }
        XCTAssertLessThan(chi2, 27.9, "chi-square, 9 dof, p = 0.001: \(counts)")
    }

    func testDegenerateSpansAreSafe() {
        let g = WheelGeometry(segmentCount: 10)
        for (a, b) in [(0.0, 0.0), (10.0, 5.0), (0.0, .nan), (0.0, .infinity)] {
            let m = SpinMotion.plan(from: a, to: b, geometry: g)
            XCTAssertTrue(m.crossingTimes.isEmpty)
            XCTAssertEqual(m.progress(at: m.duration), 1)
            XCTAssertEqual(m.progress(at: 0), 0)
        }
    }
}


/// Tap to stop: continuity, landing window, single stop, slowing ticks.
final class SpinStopTests: XCTestCase {
    private let geometry = WheelGeometry(segmentCount: 12)

    private func plan(elapsed: Double, seed: UInt64 = 7) -> (SpinMotion, SpinStopPlan?) {
        var rng = SeededRandomNumberGenerator(seed: seed)
        let start = 30.0
        let target = geometry.randomTargetRotation(from: start, using: &rng)
        let motion = SpinMotion.plan(from: start, to: target, geometry: geometry)
        return (motion, SpinStopPlan.make(motion: motion, start: start, oldTarget: target,
                                          elapsed: elapsed, geometry: geometry, using: &rng))
    }

    func testStopIsContinuousAndLandsOnNewTarget() throws {
        for elapsed in [0.0, 0.4, 1.5, 3.0] {
            let (motion, p) = plan(elapsed: elapsed)
            let stop = try XCTUnwrap(p)
            let expectedNow = stop.start + stop.span * motion.progress(at: elapsed)
            XCTAssertEqual(stop.currentAngle, expectedNow, accuracy: 1e-9)
            XCTAssertEqual(stop.displayedAngle(at: stop.startTime), stop.currentAngle, accuracy: 1e-6, "no jump at the tap")
            XCTAssertEqual(stop.displayedAngle(at: stop.endTime), stop.newTarget, accuracy: 1e-6, "settles on the new target")
            let travel = stop.newTarget - stop.currentAngle
            XCTAssertGreaterThanOrEqual(travel, SpinStopPlan.minimumTravel - 4)
            XCTAssertLessThan(travel, SpinStopPlan.minimumTravel + 360 + 4)
            // Monotonic deceleration: never moves backwards.
            var last = stop.displayedAngle(at: stop.startTime)
            for k in 1...40 {
                let a = stop.displayedAngle(at: stop.startTime + SpinStopPlan.duration * Double(k) / 40)
                XCTAssertGreaterThanOrEqual(a, last - 1e-9)
                last = a
            }
            XCTAssertEqual(SpinStopPlan.duration, 0.8)
        }
    }

    func testNoStopRightAtTheEnd() {
        let (motion, p) = plan(elapsed: 1)
        XCTAssertNotNil(p)
        let (_, late) = plan(elapsed: motion.duration - 0.5)
        XCTAssertNil(late, "within the last 0.8 s the spin just finishes")
        let (_, bad) = plan(elapsed: .nan)
        XCTAssertNil(bad)
    }

    func testStopControlAcceptsOnlyTheFirstPlan() throws {
        let (_, p1) = plan(elapsed: 1, seed: 1)
        let (_, p2) = plan(elapsed: 2, seed: 2)
        let control = SpinStopControl()
        XCTAssertNil(control.plan)
        XCTAssertTrue(control.set(try XCTUnwrap(p1)))
        XCTAssertFalse(control.set(try XCTUnwrap(p2)), "a second tap never re-targets")
        XCTAssertEqual(control.plan, p1)
    }

    func testStopPlanProgressEndpoints() throws {
        let (motion, p) = plan(elapsed: 1.0)
        let stop = try XCTUnwrap(p)
        XCTAssertEqual(SpinMotionAnimation(motion: motion, id: 1, stop: SpinStopControl()), SpinMotionAnimation(motion: motion, id: 1))
        XCTAssertEqual(stop.progress(at: stop.endTime), 1, accuracy: 1e-12)
        XCTAssertEqual(stop.progress(at: stop.startTime), stop.fromProgress, accuracy: 1e-12)
        XCTAssertEqual(stop.endTime, 1.8, accuracy: 1e-12)
    }

    func testStopTicksSlowDown() throws {
        let (_, p) = plan(elapsed: 0.5)
        let stop = try XCTUnwrap(p)
        let times = stop.crossingTimes(geometry: geometry)
        XCTAssertFalse(times.isEmpty)
        XCTAssertEqual(times, times.sorted())
        XCTAssertLessThan(times.last!, SpinStopPlan.duration)
        let gaps = zip(times.dropFirst(), times).map { $0 - $1 }
        if gaps.count >= 2 { XCTAssertGreaterThan(gaps.last!, gaps.first!, "ticks get further apart") }
    }

    func testStoppedLandingIsUniform() {
        var rng = SeededRandomNumberGenerator(seed: 99)
        var counts = [Int](repeating: 0, count: geometry.count)
        for i in 0..<6_000 {
            let t = SpinStopPlan.randomTarget(from: Double(i) * 17.3, geometry: geometry, using: &rng)
            counts[geometry.segmentIndex(forRotation: t)] += 1
        }
        for c in counts { XCTAssertEqual(Double(c), 500, accuracy: 110) }
    }
}
