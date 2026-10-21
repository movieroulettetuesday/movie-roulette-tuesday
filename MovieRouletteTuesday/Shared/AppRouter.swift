import Foundation
import Observation
import MRTCore

/// Hand-off for navigation requested from outside a view (App Intents,
/// notification taps). ContentView routes `pendingURL` exactly like `onOpenURL`.
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()
    var pendingURL: URL?
    private init() {}

    func open(_ link: DeepLink) { pendingURL = link.url }
}
