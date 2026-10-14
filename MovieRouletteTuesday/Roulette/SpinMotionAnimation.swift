import SwiftUI

/// Drives the wheel along a `SpinMotion` (the timeline of the recorded spin
/// sound): progress at each frame comes from the plan, so slice boundaries
/// pass the pointer exactly on the clip's clicks and the wheel settles as
/// the final thunk lands. Only timing; the end value is the random target.
///
/// Tap-to-stop: once `stop` holds a `SpinStopPlan`, frames from its start
/// time follow the plan's short ease-out instead and the animation ends at
/// the plan's end (the view adds the plan's static offset; see SpinStopPlan).
struct SpinMotionAnimation: CustomAnimation {
    let motion: SpinMotion
    /// Identity for equality/hashing (cheap; the plan's arrays are large).
    let id: Int
    var stop: SpinStopControl? = nil

    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        if let plan = stop?.plan, time >= plan.startTime {
            guard time < plan.endTime else { return nil }
            return value.scaled(by: plan.progress(at: time))
        }
        guard time < motion.duration else { return nil }
        return value.scaled(by: motion.progress(at: time))
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Shared between the view model (sets the plan once) and the running
/// animation (reads it every frame). Lock-protected, so it is Sendable.
final class SpinStopControl: @unchecked Sendable {
    private let lock = NSLock()
    private var _plan: SpinStopPlan?

    var plan: SpinStopPlan? {
        lock.lock(); defer { lock.unlock() }
        return _plan
    }

    /// First plan wins; later calls are ignored (no double stops).
    @discardableResult
    func set(_ plan: SpinStopPlan) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard _plan == nil else { return false }
        _plan = plan
        return true
    }
}
