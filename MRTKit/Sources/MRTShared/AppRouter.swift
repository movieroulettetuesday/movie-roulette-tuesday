import Foundation
import Observation
import MRTCore

/// Hand-off for navigation requested from outside a view (App Intents,
/// notification taps). ContentView routes `pendingURL` exactly like `onOpenURL`.
@MainActor
@Observable
public final class AppRouter {
    public static let shared = AppRouter()
    public var pendingURL: URL?
    private init() {}

    public func open(_ link: DeepLink) { pendingURL = link.url }
}
