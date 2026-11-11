import AppIntents
import SwiftUI

/// “What should I watch in Movie Roulette”: an on-device suggestion with a
/// short why, or an offer to Spin (never an automatic spin).
struct WhatShouldIWatchIntent: AppIntent {
    static let title: LocalizedStringResource = "What Should I Watch"
    static let description = IntentDescription(
        "Picks a catalog movie for tonight, with a short reason, using the on-device model.",
        categoryName: "Roulette"
    )
    static let openAppWhenRun = false
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let outcome = await SuggestionGenerator.generate()
        switch outcome {
        case .suggestion(let accepted):
            let catalog = try? await IntentCatalog.load()
            let movie = catalog.flatMap { $0.movie(withId: accepted.movieId) }
            let title = movie?.title ?? accepted.movieId
            return .result(
                dialog: IntentDialog(stringLiteral: SuggestionSpeech.success(title: title, why: accepted.why)),
                view: SuggestionSnippetView(movie: movie, catalog: catalog, why: accepted.why)
            )
        case .notReady:
            return .result(
                dialog: IntentDialog(stringLiteral: SuggestionSpeech.notReady),
                view: SuggestionFallbackSnippet(message: SuggestionSpeech.notReady)
            )
        case .offerSpin(let reason):
            let message = reason == .unavailable ? SuggestionSpeech.unavailable : SuggestionSpeech.failed
            return .result(
                dialog: IntentDialog(stringLiteral: message),
                view: SuggestionFallbackSnippet(message: message)
            )
        }
    }
}
