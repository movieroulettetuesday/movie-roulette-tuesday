import Foundation
import Observation

protocol SuggestionResponding: Sendable {
    func suggest(prompt: String) async throws -> WatchSuggestionDraft
}

/// Shared by the Roulette-tab button and `WhatShouldIWatchIntent`.
/// Tests inject a stub session; the live path uses only `SystemLanguageModel.default`.
@MainActor
enum SuggestionGenerator {
    static var responder: (() -> any SuggestionResponding)?

    static func reset() {
        responder = nil
    }

    static func generate() async -> SuggestionOutcome {
        let status = SuggestionAvailability.current()
        switch SuggestionGate.entry(for: status) {
        case .hidden: return .offerSpin(.unavailable)
        case .notReady: return .notReady
        case .ready: break
        }

        #if DEBUG
        if let stub = DebugLaunch.suggestionStub {
            return .suggestion(stub)
        }
        #endif

        guard let catalog = try? await IntentCatalog.load() else {
            return .offerSpin(.failed)
        }
        let ratings = IntentRuntime.ratings().ratings
        let history = IntentRuntime.history().results
        let services = MyServices(
            serialized: IntentRuntime.defaults().string(forKey: MyServices.storageKey) ?? ""
        )
        let context = SuggestionPrompt.context(
            catalog: catalog,
            ratings: ratings,
            recentIDs: SuggestionPrompt.recentIDs(from: history),
            services: services
        )
        let prompt = SuggestionPrompt.prompt(from: context)
        let ids = Set(catalog.movies.map(\.id))

        guard let session = responder?() ?? defaultResponder() else {
            return .offerSpin(.failed)
        }

        var attempts: [Result<WatchSuggestionDraft, Error>] = []
        for _ in 0..<2 {
            do {
                let draft = try await session.suggest(prompt: prompt)
                attempts.append(.success(draft))
                if SuggestionValidation.accept(draft, catalogIDs: ids) != nil { break }
            } catch {
                attempts.append(.failure(error))
            }
        }
        return SuggestionResolver.resolve(attempts: attempts, catalogIDs: ids)
    }

    static func defaultResponder() -> (any SuggestionResponding)? {
        if #available(iOS 26.0, *) {
            return systemResponder()
        }
        return nil
    }

    @available(iOS 26.0, *)
    private static func systemResponder() -> (any SuggestionResponding)? {
        #if canImport(FoundationModels)
        return OnDeviceSuggestionSession()
        #else
        return nil
        #endif
    }
}

@MainActor
@Observable
final class SuggestionController {
    var entry: SuggestionEntry = .hidden
    var outcome: SuggestionOutcome?
    var isLoading = false
    var presented = false

    var showsButton: Bool { entry != .hidden }

    func refresh() {
        entry = SuggestionGate.entry(for: SuggestionAvailability.current())
    }

    func tap() async {
        // Set the visible state before presenting so a form-sized sheet
        // doesn't first land on an empty ProgressView and collapse.
        refresh()
        switch entry {
        case .hidden:
            isLoading = false
            outcome = .offerSpin(.unavailable)
        case .notReady:
            isLoading = false
            outcome = .notReady
        case .ready:
            isLoading = true
            outcome = nil
        }
        presented = true
        guard entry == .ready else { return }
        outcome = await SuggestionGenerator.generate()
        isLoading = false
    }

    func dismiss() {
        presented = false
        outcome = nil
        isLoading = false
    }
}
