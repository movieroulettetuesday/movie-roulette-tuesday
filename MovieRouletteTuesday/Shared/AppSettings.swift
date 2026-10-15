import Foundation

/// `@AppStorage` keys (Settings sheet) plus defaults for non-view code.
enum AppSettings {
    /// "Spin sound" (the key predates the recorded clip; kept so preferences carry over).
    static let tickSound = "settings.tickSound"
    static let haptics = "settings.haptics"
    static let rareOutcomes = "settings.rareOutcomes"
    /// "1.0 (8)": marketing version and build, for Credits & About.
    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
    /// When on, setting "my rating" also submits the anonymous listener rating.
    static let autoShareRatings = "settings.autoShareRatings"

    static let defaults: [String: Bool] = [
        tickSound: true,
        haptics: true,
        rareOutcomes: true,
        autoShareRatings: false,
    ]

    static func bool(_ key: String, store: UserDefaults = .standard) -> Bool {
        store.object(forKey: key) as? Bool ?? defaults[key] ?? false
    }

    static let privacyNote = "This app collects no personal data. Ratings, watchlist, and spin history stay on your device. Poll votes and listener ratings are stored anonymously in iCloud with no name or account attached. Listen links, movie list updates, the optional new-episode check, and Apple’s episode lookup only fetch the show’s public pages, feed, and movie list; nothing about you is sent. A movie suggestion is an email you send yourself from Mail."
}
