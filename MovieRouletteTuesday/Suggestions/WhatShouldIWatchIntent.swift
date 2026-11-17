import AppIntents
import SwiftUI

/// "Pick a movie for me in Movie Roulette": one movie chosen on purpose, with
/// facts from your own lists, or an offer to Spin when the on-device model
/// can't run here (never an automatic spin). The type name stays so existing
/// Shortcuts that use this action keep working.
struct WhatShouldIWatchIntent: AppIntent {
    static let title: LocalizedStringResource = "Pick for Me"
    static let description = IntentDescription(
        "Picks one movie for tonight from the catalog and says why, on this device.",
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
            return .result(
                dialog: IntentDialog(stringLiteral: SuggestionSpeech.success(accepted)),
                view: SuggestionSnippetView(movie: movie, catalog: catalog, accepted: accepted)
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
