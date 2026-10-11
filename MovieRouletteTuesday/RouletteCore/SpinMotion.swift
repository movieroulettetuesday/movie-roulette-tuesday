import Foundation

/// The wheel's motion for one spin, locked to the recorded spin sound.
///
/// Base curve: the wheel's speed follows the recording's click rate (the
/// ratchet slows from ~53 to ~44 clicks/s), ramping up over the clip's
/// wind-up, then brakes to rest inside the final thunk's decay. Progress
/// 0 -> 1 is mapped onto `start -> end` rotation, and `end` is the uniformly
/// random target from `WheelGeometry.randomTargetRotation`; only the timing
/// changes, never where the wheel lands.
///
/// Click lock: each slice-boundary crossing is moved (by at most
/// `maxSnap`, typically a few ms) onto a click onset of the clip, chosen so
/// the local speed stays as even as possible, via a smooth monotone time
/// warp, so the pointer passes a boundary exactly when a click is heard. Haptics fire at `crossingTimes`, the same instants.
public struct SpinMotion: Hashable, Sendable {
    /// Time-warp knots: real time -> base-curve time (both ascending, 0...duration).
    public let realKnots: [Double]
    public let baseKnots: [Double]
    /// Visual spin length (last click + brake).
    public let duration: Double
    /// Real times of the boundary crossings (ascending).
    public let crossingTimes: [Double]
    /// How far each crossing moved to land on a click (s; 0 = no snap possible).
    public let snapOffsets: [Double]

    /// Largest shift a crossing may take to land on a click.
    public static let maxSnap = 0.012
    /// Base curve sampling step.
    static let step = 0.001

    /// Cumulative base progress (unnormalised) sampled every `step` s, 0...spinDuration.
    static let baseTable: [Double] = {
        let track = SpinSoundTrack.self
        let n = Int((track.spinDuration / step).rounded(.up)) + 1
        var cum = [Double](repeating: 0, count: n)
        let stopSpeed = speed(atBase: track.stopTime)
        var acc = 0.0
        for i in 1..<n {
            let t = (Double(i) - 0.5) * step
            let v: Double
            if t < track.stopTime {
                v = speed(atBase: t)
            } else {
                // Brake: speed falls linearly to 0 within the thunk's decay.
                let u = min(1, (t - track.stopTime) / track.brakeDuration)
                v = stopSpeed * (1 - u)
            }
            acc += v * step
            cum[i] = acc
        }
        return cum.map { $0 / acc }
    }()

    /// Clicks per second (∝ wheel speed) with the wind-up ramp.
    static func speed(atBase t: Double) -> Double {
        let track = SpinSoundTrack.self
        let period = track.periodIntercept + track.periodSlope * max(0, t)
        let x = min(max(t / track.windUp, 0), 1)
        let ramp = 0.2 + 0.8 * x * x * (3 - 2 * x)
        return ramp / period
    }

    /// Base progress (0...1) at base time `t` (0...spinDuration).
    public static func baseProgress(at t: Double) -> Double {
        let table = baseTable
        guard t > 0 else { return 0 }
        let f = t / step
        let i = Int(f)
        guard i + 1 < table.count else { return 1 }
        return table[i] + (table[i + 1] - table[i]) * (f - Double(i))
    }

    /// Base time at which progress `p` is reached (inverse of `baseProgress`).
    public static func baseTime(atProgress p: Double) -> Double {
        let table = baseTable
        guard p > 0 else { return 0 }
        guard p < 1 else { return SpinSoundTrack.spinDuration }
        var lo = 0, hi = table.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if table[mid] < p { lo = mid } else { hi = mid }
        }
        let span = table[hi] - table[lo]
        let frac = span > 0 ? (p - table[lo]) / span : 0
        return (Double(lo) + frac) * step
    }

    /// Plans a spin from `start` to `end` rotation (degrees) for `geometry`.
    public static func plan(from start: Double, to end: Double, geometry: WheelGeometry,
                            onsets: [Double] = SpinSoundTrack.onsets) -> SpinMotion {
        let duration = SpinSoundTrack.spinDuration
        let span = end - start
        var real: [Double] = [0], base: [Double] = [0], crossings: [Double] = [], offsets: [Double] = []
        guard span > 0, span.isFinite else {
            return SpinMotion(realKnots: [0, duration], baseKnots: [0, duration], duration: duration,
                              crossingTimes: [], snapOffsets: [])
        }
        // Base-curve times of the boundary crossings.
        var taus: [Double] = []
        for rotation in SpinTicks.boundaryRotations(from: start, to: end, geometry: geometry) {
            let tau = baseTime(atProgress: (rotation - start) / span)
            guard tau > 0.001, tau < duration - 0.001, tau > (taus.last ?? 0) + 0.0005 else { continue }
            taus.append(tau)
        }
        // Candidates per knot: every click within `maxSnap`, or no snap (penalised).
        // Knot 0 = start, last knot = end of the spin.
        var cands: [[Double]] = [[0]]
        var snapped: [[Bool]] = [[false]]
        for tau in taus {
            var c: [Double] = [], f: [Bool] = []
            if tau < SpinSoundTrack.stopTime {
                for onset in clickOnsets(near: tau, in: onsets) where onset < SpinSoundTrack.stopTime {
                    c.append(onset); f.append(true)
                }
            }
            c.append(tau); f.append(false)
            cands.append(c); snapped.append(f)
        }
        cands.append([duration]); snapped.append([false])
        let knotBase = [0] + taus + [duration]
        let choice = smoothestChoice(cands: cands, snapped: snapped, base: knotBase)
        for k in 1..<(knotBase.count - 1) {
            let t = cands[k][choice[k]]
            real.append(t); base.append(knotBase[k])
            crossings.append(t); offsets.append(t - knotBase[k])
        }
        real.append(duration); base.append(duration)
        return SpinMotion(realKnots: real, baseKnots: base, duration: duration,
                          crossingTimes: crossings, snapOffsets: offsets)
    }

    /// Penalty for leaving a crossing off the clicks (≈ a 100% speed change).
    static let missPenalty = 0.5

    /// Picks one candidate per knot (dynamic programming over consecutive
    /// pairs) so crossings land on clicks while the local speed changes as
    /// little as possible: minimises Σ ln(slope_k / slope_k-1)² + misses.
    static func smoothestChoice(cands: [[Double]], snapped: [[Bool]], base: [Double]) -> [Int] {
        let n = cands.count
        guard n > 2 else { return [Int](repeating: 0, count: n) }
        func gap(_ k: Int) -> Double { (k == 1 || k == n - 1) ? 0.002 : 0.004 }
        func pen(_ k: Int, _ j: Int) -> Double { (k > 0 && k < n - 1 && !snapped[k][j]) ? missPenalty : 0 }
        // cost[k][j][i]: best cost with knot k = j, knot k-1 = i.
        var cost = [[[Double]]](); var back = [[[Int]]]()
        let inf = Double.infinity
        cost.append([[0]]); back.append([[0]])
        cost.append(cands[1].indices.map { j in
            [cands[1][j] > cands[0][0] + gap(1) ? pen(1, j) : inf]
        })
        back.append(cands[1].indices.map { _ in [0] })
        for k in 2..<n {
            var ck = [[Double]](), bk = [[Int]]()
            for l in cands[k].indices {
                var row = [Double](), brow = [Int]()
                for j in cands[k - 1].indices {
                    var best = inf, arg = 0
                    let t1 = cands[k - 1][j], t2 = cands[k][l]
                    if t2 > t1 + gap(k) {
                        let s2 = (base[k] - base[k - 1]) / (t2 - t1)
                        for i in cands[k - 2].indices where cost[k - 1][j][i] < inf {
                            let t0 = cands[k - 2][i]
                            let s1 = (base[k - 1] - base[k - 2]) / (t1 - t0)
                            let r = log(s2 / s1)
                            let c = cost[k - 1][j][i] + r * r + pen(k, l)
                            if c < best { best = c; arg = i }
                        }
                    }
                    row.append(best); brow.append(arg)
                }
                ck.append(row); bk.append(brow)
            }
            cost.append(ck); back.append(bk)
        }
        // Trace back from the end knot.
        var choice = [Int](repeating: cands.count, count: n)
        var bestJ = -1, bestCost = inf
        for j in cands[n - 2].indices where cost[n - 1][0][j] < bestCost { bestCost = cost[n - 1][0][j]; bestJ = j }
        guard bestJ >= 0 else {
            // No feasible path (cannot happen: unsnapped taus are always increasing); stay unsnapped.
            return cands.map { $0.count - 1 }
        }
        choice[n - 1] = 0; choice[n - 2] = bestJ
        if n - 3 >= 0 {
            for k in stride(from: n - 1, through: 2, by: -1) {
                choice[k - 2] = back[k][choice[k]][choice[k - 1]]
            }
        }
        return choice
    }

    /// Click onsets within `maxSnap` of `t` (ascending).
    static func clickOnsets(near t: Double, in sorted: [Double]) -> [Double] {
        guard !sorted.isEmpty else { return [] }
        var lo = 0, hi = sorted.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if sorted[mid] < t - maxSnap { lo = mid + 1 } else { hi = mid }
        }
        var out: [Double] = []
        var i = lo
        while i < sorted.count, sorted[i] <= t + maxSnap { out.append(sorted[i]); i += 1 }
        return out
    }

    /// Progress (0...1) at real time `t`; exactly the boundary progress at each crossing.
    public func progress(at t: Double) -> Double {
        guard t > 0 else { return 0 }
        guard t < duration else { return 1 }
        // Find the knot interval (binary search), then map real -> base time
        // with a monotone cubic (Fritsch–Carlson), so the speed stays smooth.
        var lo = 0, hi = realKnots.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if realKnots[mid] <= t { lo = mid } else { hi = mid }
        }
        return Self.baseProgress(at: warp(t, lo))
    }

    private func slope(_ i: Int) -> Double {
        (baseKnots[i + 1] - baseKnots[i]) / (realKnots[i + 1] - realKnots[i])
    }

    private func tangent(_ i: Int) -> Double {
        let n = realKnots.count
        if i == 0 { return slope(0) }
        if i == n - 1 { return slope(n - 2) }
        let a = slope(i - 1), b = slope(i)
        guard a > 0, b > 0 else { return 0 }
        return 2 / (1 / a + 1 / b)   // harmonic mean: monotone, no overshoot
    }

    private func warp(_ t: Double, _ i: Int) -> Double {
        let x0 = realKnots[i], x1 = realKnots[i + 1], y0 = baseKnots[i], y1 = baseKnots[i + 1]
        let h = x1 - x0
        let s = (t - x0) / h
        let m0 = tangent(i) * h, m1 = tangent(i + 1) * h
        let s2 = s * s, s3 = s2 * s
        let y = (2 * s3 - 3 * s2 + 1) * y0 + (s3 - 2 * s2 + s) * m0 + (-2 * s3 + 3 * s2) * y1 + (s3 - s2) * m1
        return min(max(y, y0), y1)
    }
}
