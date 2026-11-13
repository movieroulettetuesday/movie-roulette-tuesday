import AppIntents
import SwiftUI
import MRTCore
import MRTShared

/// Spoken lines shared with the iOS step-2 intent. On tvOS the on-device
/// model is `@available(tvOS, unavailable)` in the 27.2 SDK, so every
/// entry offers Spin and does not spin on its own.
enum SuggestionSpeech {
    static let unavailable = "Suggestions aren’t available on this device. I can spin the wheel instead."
    static let notReady = "Suggestions aren’t ready yet. I can spin the wheel instead."
    static let failed = "I couldn’t pick a movie right now. I can spin the wheel instead."
}

/// “What should I watch in Movie Roulette” on Apple TV: always offers Spin.
/// There is no in-app button (a Spin-only button would duplicate the wheel).
struct WhatShouldIWatchIntent: AppIntent {
    static let title: LocalizedStringResource = "What Should I Watch"
    static let description = IntentDescription(
        "Offers to spin the wheel. On-device suggestions aren’t available on Apple TV.",
        categoryName: "Roulette"
    )
    static let openAppWhenRun = false
    @available(iOS 26.0, tvOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        // Never calls Foundation Models. Never auto-spins.
        return .result(
            dialog: IntentDialog(stringLiteral: SuggestionSpeech.unavailable),
            view: SuggestionFallbackSnippet(message: SuggestionSpeech.unavailable)
        )
    }
}

struct SuggestionFallbackSnippet: View {
    var message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                FilmBadge(size: 26)
                Text("MOVIE ROULETTE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
            }
            Text(message).font(.body)
            Button(intent: SpinMovieRouletteIntent()) {
                Text("Spin the Wheel")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Brand.teal.opacity(0.18), in: Capsule())
                    .foregroundStyle(Brand.teal)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
    }
}
