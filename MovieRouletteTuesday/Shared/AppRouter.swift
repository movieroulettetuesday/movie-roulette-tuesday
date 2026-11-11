import Foundation
import Observation

/// One Siri spin that history already contains. The wheel plays this result
/// and does not pick or record another one.
struct PendingSpin: Equatable, Sendable {
    var movieID: String
    var landedCategoryID: String
    var creditedCategoryID: String
    var isJackpot: Bool
    var resultID: UUID
}

/// Hand-off for navigation requested from outside a view (App Intents,
/// notification taps). ContentView routes `pendingURL` exactly like `onOpenURL`.
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()
    var pendingURL: URL?
    /// Written before `pendingURL` on a spin, so the route and the payload arrive together.
    var pendingSpin: PendingSpin?
    private init() {}

    func open(_ link: DeepLink) { pendingURL = link.url }

    func handOffSpin(_ spin: PendingSpin) {
        pendingSpin = spin
        pendingURL = DeepLink.spin.url
    }

    func takePendingSpin() -> PendingSpin? {
        let spin = pendingSpin
        pendingSpin = nil
        return spin
    }
}
