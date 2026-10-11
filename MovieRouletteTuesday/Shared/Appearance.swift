import SwiftUI
import UIKit

extension AppearancePreference {
    var colorScheme: ColorScheme? {
        forcesDark.map { $0 ? .dark : .light }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        forcesDark.map { $0 ? .dark : .light } ?? .unspecified
    }
}

/// Applies Settings → Appearance. `preferredColorScheme` drives SwiftUI; the
/// window override makes "System" reliably revert after Light/Dark (passing
/// nil to preferredColorScheme alone doesn't always reset) and covers every
/// sheet presented from that window.
struct AppAppearanceModifier: ViewModifier {
    @AppStorage(AppearancePreference.storageKey) private var stored = AppearancePreference.default.rawValue

    private var preference: AppearancePreference { AppearancePreference(storedValue: stored) }

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(preference.colorScheme)
            .onAppear { Self.applyToWindows(preference) }
            .onChange(of: stored) { _, _ in Self.applyToWindows(preference) }
    }

    @MainActor
    static func applyToWindows(_ preference: AppearancePreference) {
        let style = preference.interfaceStyle
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where window.overrideUserInterfaceStyle != style {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}

extension View {
    /// Apply at the app root and on presented sheets.
    func appAppearance() -> some View {
        modifier(AppAppearanceModifier())
    }
}
