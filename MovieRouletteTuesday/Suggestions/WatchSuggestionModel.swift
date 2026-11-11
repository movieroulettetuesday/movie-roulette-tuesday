import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Guided-generation shape for the on-device model. Never sent off-device.
@available(iOS 26.0, *)
@Generable
struct WatchSuggestion {
    @Guide(description: "Catalog movie id, copied exactly from the context.")
    var movieId: String

    @Guide(description: "One or two sentences on why this movie fits tonight.")
    var why: String
}

/// On-device session only. Does not construct or pass a Private Cloud Compute model.
@available(iOS 26.0, *)
struct OnDeviceSuggestionSession: SuggestionResponding {
    func suggest(prompt: String) async throws -> WatchSuggestionDraft {
        let session = LanguageModelSession(
            model: SystemLanguageModel.default,
            instructions: SuggestionPrompt.instructions
        )
        let response = try await session.respond(to: prompt, generating: WatchSuggestion.self)
        return WatchSuggestionDraft(movieId: response.content.movieId, why: response.content.why)
    }
}
#endif

#if canImport(FoundationModels)
@available(iOS 26.0, *)
extension SuggestionAvailability {
    static func mapSystemAvailability() -> SuggestionModelStatus {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .modelNotReady:
                return .temporarilyUnavailable
            case .deviceNotEligible, .appleIntelligenceNotEnabled:
                return .unavailable
            @unknown default:
                return .unavailable
            }
        }
    }
}
#endif
