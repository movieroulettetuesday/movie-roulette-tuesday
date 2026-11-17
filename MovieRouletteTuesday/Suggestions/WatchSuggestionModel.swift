import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Guided-generation shape for the on-device model: a number from the list and
/// a vibe from a fixed set. No free text. Never sent off-device.
@available(iOS 26.0, *)
@Generable
struct WatchPick {
    @Guide(description: "The number of the chosen movie in the list.", .range(1...PickCandidates.cap))
    var pick: Int

    @Guide(description: "One vibe that suits the movie's genre.", .anyOf(PickVibe.allCases.map(\.rawValue)))
    var vibe: String
}

/// On-device session only. Does not construct or pass a Private Cloud Compute model.
/// One prewarmed session waits for the next tap; each answer uses it once
/// (single turn) and a fresh one is prewarmed for the tap after.
@available(iOS 26.0, *)
final class OnDeviceSuggestionSession: SuggestionResponding, @unchecked Sendable {
    /// A runaway guard only; a real answer is about 10 tokens.
    static let maximumResponseTokens = 24

    private let lock = NSLock()
    private var waiting: LanguageModelSession?

    private func makeSession() -> LanguageModelSession {
        LanguageModelSession(model: SystemLanguageModel.default, instructions: PickPrompt.instructions)
    }

    private func takeSession() -> LanguageModelSession {
        lock.lock()
        defer { lock.unlock() }
        let session = waiting ?? makeSession()
        waiting = nil
        return session
    }

    func prewarm() {
        lock.lock()
        let session = waiting ?? makeSession()
        waiting = session
        lock.unlock()
        session.prewarm()
    }

    func pick(prompt: String) async throws -> RawPick {
        let session = takeSession()
        defer { prewarm() }
        let options = GenerationOptions(temperature: 0.3, maximumResponseTokens: Self.maximumResponseTokens)
        let response = try await session.respond(to: prompt, generating: WatchPick.self, options: options)
        return RawPick(pick: response.content.pick, vibe: response.content.vibe)
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
