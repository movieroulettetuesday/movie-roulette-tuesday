import Foundation
import Observation
import MRTCore

/// One Siri spin that history already contains. The wheel plays this result
/// and does not pick or record another one.
public struct PendingSpin: Equatable, Sendable {
    public var movieID: String
    public var landedCategoryID: String
    public var creditedCategoryID: String
    public var isJackpot: Bool
    public var resultID: UUID

    public init(movieID: String, landedCategoryID: String, creditedCategoryID: String, isJackpot: Bool, resultID: UUID) {
        self.movieID = movieID
        self.landedCategoryID = landedCategoryID
        self.creditedCategoryID = creditedCategoryID
        self.isJackpot = isJackpot
        self.resultID = resultID
    }
}

/// Hand-off for navigation requested from outside a view (App Intents,
/// notification taps, Top Shelf). TVRootView and ContentView route
/// `pendingURL` exactly like `onOpenURL`.
@MainActor
@Observable
public final class AppRouter {
    public static let shared = AppRouter()
    public var pendingURL: URL?
    /// Written before `pendingURL` on a spin, so the route and the payload arrive together.
    public var pendingSpin: PendingSpin?
    private init() {}

    public func open(_ link: DeepLink) { pendingURL = link.url }

    public func handOffSpin(_ spin: PendingSpin) {
        pendingSpin = spin
        pendingURL = DeepLink.spin.url
    }

    public func takePendingSpin() -> PendingSpin? {
        let spin = pendingSpin
        pendingSpin = nil
        return spin
    }
}
