import AppIntents
import SwiftUI

enum PickForMeCopy {
    static let buttonTitle = "Pick for Me"
    static let buttonSubtitle = "Not random: one movie chosen for you, and why it fits."
    static let accessibilityHint = "Picks one movie for you on purpose and explains why. Not random."
    static let sheetTitle = "Picked for You"
    static let loading = "Picking from your watchlist and services…"
}

struct PickForMeButton: View {
    var action: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Button(action: action) {
                Text(PickForMeCopy.buttonTitle)
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Brand.teal, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            // Identifier kept from 1.0 so existing UI tests and scripts still find it.
            .accessibilityIdentifier("what-should-i-watch-button")
            .accessibilityHint(PickForMeCopy.accessibilityHint)
            Text(PickForMeCopy.buttonSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("pick-for-me-subtitle")
        }
    }
}

struct SuggestionSheet: View {
    @Bindable var controller: SuggestionController
    var catalog: MovieCatalog?
    var onOpenMovie: (String) -> Void
    var onSpinInstead: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if controller.isLoading {
                    loadingView
                } else {
                    content
                }
            }
            .background { CleanProBackground() }
            .navigationTitle(PickForMeCopy.sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { controller.dismiss() }
                }
            }
        }
        .appAppearance()
        .adaptiveSheetSizing()
    }

    @ViewBuilder
    private var content: some View {
        switch controller.outcome {
        case .suggestion(let accepted):
            let movie = catalog?.movie(withId: accepted.movieId)
            SuggestionCard(
                movie: movie,
                catalog: catalog,
                accepted: accepted,
                onOpenMovie: { onOpenMovie(accepted.movieId) },
                onWhereToWatch: { onOpenMovie(accepted.movieId) },
                onSpinInstead: onSpinInstead
            )
        case .notReady:
            SuggestionFallbackCard(message: SuggestionSpeech.inAppNotReady, onSpinInstead: onSpinInstead)
        case .offerSpin(let reason):
            let message = reason == .unavailable ? SuggestionSpeech.unavailable : SuggestionSpeech.failed
            SuggestionFallbackCard(message: message, onSpinInstead: onSpinInstead)
        case nil:
            loadingView
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(PickForMeCopy.loading)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("suggestion-loading-text")
            HStack(spacing: 20) {
                Button("Cancel") { controller.dismiss() }
                    .accessibilityIdentifier("suggestion-loading-cancel")
                Button("Spin instead", action: onSpinInstead)
                    .accessibilityIdentifier("suggestion-loading-spin-instead")
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("suggestion-loading")
    }
}

struct SuggestionCard: View {
    var movie: Movie?
    var catalog: MovieCatalog?
    var accepted: AcceptedSuggestion
    var onOpenMovie: () -> Void
    var onWhereToWatch: () -> Void
    var onSpinInstead: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 14) {
                    Image("roulette.wheel")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 54, height: 54)
                        .foregroundStyle(Brand.teal)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        if let movie {
                            Text(movie.genre.uppercased())
                                .font(.caption2.weight(.heavy))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Brand.teal.opacity(0.18), in: Capsule())
                                .foregroundStyle(Brand.teal)
                            Text(movie.title)
                                .font(.title3.bold())
                                .lineLimit(2)
                                .accessibilityIdentifier("suggestion-title")
                            Text(subtitle(for: movie))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        } else {
                            Text("A catalog movie")
                                .font(.title3.bold())
                                .accessibilityIdentifier("suggestion-title")
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("WHY")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if let lead = accepted.lead {
                        Text(lead)
                            .font(.body)
                            .accessibilityIdentifier("suggestion-why")
                    }
                    if !accepted.facts.isEmpty {
                        Text(accepted.factsLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(accepted.facts.map(\.text).joined(separator: ", "))
                            .accessibilityIdentifier("suggestion-facts")
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Brand.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                HStack(spacing: 10) {
                    cardButton("Open Movie", fill: Brand.teal.opacity(0.18), ink: Brand.teal, id: "suggestion-open-movie", action: onOpenMovie)
                    cardButton("Where to Watch", fill: Color.primary.opacity(0.08), ink: .primary, id: "suggestion-where-to-watch", action: onWhereToWatch)
                    cardButton("Spin instead", fill: Color.primary.opacity(0.08), ink: .primary, id: "suggestion-spin-instead", action: onSpinInstead)
                }
            }
            .padding(20)
        }
        .accessibilityIdentifier("suggestion-card")
    }

    private func subtitle(for movie: Movie) -> String {
        catalog?.subtitle(for: movie) ?? "\(movie.year) · \(movie.genre)"
    }

    private func cardButton(_ title: String, fill: Color, ink: Color, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(fill, in: Capsule())
                .foregroundStyle(ink)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

struct SuggestionFallbackCard: View {
    var message: String
    var onSpinInstead: () -> Void

    var body: some View {
        // ScrollView, like SuggestionCard: an identifier on a bare VStack
        // overwrites the child identifiers (the message and Spin button
        // were both reporting "suggestion-fallback" to XCTest).
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(message)
                    .font(.body)
                    .accessibilityIdentifier("suggestion-fallback-message")
                Button(action: onSpinInstead) {
                    Text("Spin the Wheel")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Brand.teal.opacity(0.18), in: Capsule())
                        .foregroundStyle(Brand.teal)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("suggestion-spin-the-wheel")
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .accessibilityIdentifier("suggestion-fallback")
    }
}

/// Siri / Shortcuts snippet: same card, with App Intent buttons.
struct SuggestionSnippetView: View {
    var movie: Movie?
    var catalog: MovieCatalog?
    var accepted: AcceptedSuggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                FilmBadge(size: 26)
                Text("MOVIE ROULETTE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
            }
            if let movie {
                HStack(alignment: .center, spacing: 14) {
                    Image("roulette.wheel").resizable().scaledToFit().frame(width: 54, height: 54)
                        .foregroundStyle(Brand.teal)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(movie.genre.uppercased())
                            .font(.caption2.weight(.heavy))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Brand.teal.opacity(0.18), in: Capsule())
                            .foregroundStyle(Brand.teal)
                        Text(movie.title).font(.title3.bold()).lineLimit(2)
                        Text(catalog?.subtitle(for: movie) ?? "\(movie.year) · \(movie.genre)")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Text(["Try \(movie.title).", accepted.lead].compactMap { $0 }.joined(separator: " "))
                    .font(.subheadline)
                if !accepted.facts.isEmpty {
                    Text(accepted.factsLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                if let movie, let catalog {
                    let entity = MovieEntity(movie: movie, catalog: catalog)
                    snippetButton("Open Movie", intent: {
                        let intent = OpenMovieIntent()
                        intent.movie = entity
                        return intent
                    }(), fill: Brand.teal.opacity(0.18), ink: Brand.teal)
                    snippetButton("Where to Watch", intent: {
                        let intent = WhereToWatchIntent()
                        intent.movie = entity
                        return intent
                    }(), fill: Color.primary.opacity(0.08), ink: .primary)
                }
                snippetButton("Spin instead", intent: SpinMovieRouletteIntent(), fill: Color.primary.opacity(0.08), ink: .primary)
            }
        }
        .padding(18)
    }

    private func snippetButton<I: AppIntent>(_ title: String, intent: I, fill: Color, ink: Color) -> some View {
        Button(intent: intent) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(fill, in: Capsule())
                .foregroundStyle(ink)
        }
        .buttonStyle(.plain)
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
