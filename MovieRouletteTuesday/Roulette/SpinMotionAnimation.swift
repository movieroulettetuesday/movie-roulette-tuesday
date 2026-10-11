import SwiftUI

/// Drives the wheel along a `SpinMotion` (the timeline of the recorded spin
/// sound): progress at each frame comes from the plan, so slice boundaries
/// pass the pointer exactly on the clip's clicks and the wheel settles as
/// the final thunk lands. Only timing; the end value is the random target.
struct SpinMotionAnimation: CustomAnimation {
    let motion: SpinMotion
    /// Identity for equality/hashing (cheap; the plan's arrays are large).
    let id: Int

    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        guard time < motion.duration else { return nil }
        return value.scaled(by: motion.progress(at: time))
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
