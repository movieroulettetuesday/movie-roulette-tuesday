import Foundation

/// App appearance setting (Settings → Appearance). Stored as its raw value in
/// UserDefaults via `@AppStorage(AppearancePreference.storageKey)`.
public enum AppearancePreference: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public static let storageKey = "settings.appearance"
    public static let `default`: AppearancePreference = .system

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// Missing or unrecognized stored values fall back to following the system.
    public init(storedValue: String?) {
        self = storedValue.flatMap(AppearancePreference.init(rawValue:)) ?? .default
    }

    /// `nil` = follow the system; `true` = force dark; `false` = force light.
    /// (SwiftUI maps this to `preferredColorScheme(nil / .light / .dark)`.)
    public var forcesDark: Bool? {
        switch self {
        case .system: return nil
        case .light: return false
        case .dark: return true
        }
    }
}
