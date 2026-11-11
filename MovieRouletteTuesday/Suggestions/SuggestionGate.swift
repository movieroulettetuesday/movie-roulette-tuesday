import Foundation

/// Whether the on-device Foundation Model can produce a suggestion.
/// Independent of the Framework so it compiles and is testable on iOS 17.
enum SuggestionModelStatus: Equatable, Sendable {
    /// `SystemLanguageModel.default.availability == .available`.
    case available
    /// `.unavailable(.modelNotReady)` — temporary. The in-app button stays visible.
    case temporarilyUnavailable
    /// Ineligible, Apple Intelligence off, iOS < 26, or any other reason.
    case unavailable
}

/// What the Roulette tab shows for “What should I watch?”
enum SuggestionEntry: Equatable, Sendable {
    /// Hide the button. The tab looks like it does today. Siri offers Spin.
    case hidden
    /// Show the button; tapping asks the on-device model for a suggestion.
    case ready
    /// Show the button; tapping says suggestions aren’t ready yet. Siri offers Spin.
    case notReady
}

enum SuggestionGate {
    static func entry(for status: SuggestionModelStatus) -> SuggestionEntry {
        switch status {
        case .available: return .ready
        case .temporarilyUnavailable: return .notReady
        case .unavailable: return .hidden
        }
    }

    /// The Siri intent offers Spin (and does not spin on its own) whenever
    /// it cannot return a suggestion.
    static func intentOffersSpin(for status: SuggestionModelStatus) -> Bool {
        status != .available
    }
}

enum SuggestionSpeech {
    static let unavailable = "Suggestions aren’t available on this device. I can spin the wheel instead."
    static let notReady = "Suggestions aren’t ready yet. I can spin the wheel instead."
    static let failed = "I couldn’t pick a movie right now. I can spin the wheel instead."
    static let inAppNotReady = "Suggestions aren’t ready yet. Try again in a moment."

    static func success(title: String, why: String) -> String {
        "Try \(title). \(why)"
    }
}

/// Reads the system (or a test override). Never touches Private Cloud Compute.
@MainActor
enum SuggestionAvailability {
    /// Unit tests set this. `nil` falls through to launch arguments (DEBUG) or the system.
    static var override: SuggestionModelStatus?

    static func reset() { override = nil }

    static func current() -> SuggestionModelStatus {
        if let override { return override }
        #if DEBUG
        if let forced = DebugLaunch.suggestionStatus { return forced }
        #endif
        guard #available(iOS 26.0, *) else { return .unavailable }
        return systemStatus()
    }

    @available(iOS 26.0, *)
    private static func systemStatus() -> SuggestionModelStatus {
        #if canImport(FoundationModels)
        return mapSystemAvailability()
        #else
        return .unavailable
        #endif
    }
}
