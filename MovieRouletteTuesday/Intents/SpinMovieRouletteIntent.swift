import AppIntents
import SwiftUI

/// "Hey Siri, spin Movie Roulette": one `QuickSpin`, recorded once, then the
/// app opens and the wheel plays that same result. The v4 snippet is the
/// confirmation. App Intents run in this process, so `SpinHistoryStore.shared`
/// is the history the wheel already shows.
struct SpinMovieRouletteIntent: AppIntent {
    static let title: LocalizedStringResource = "Spin Movie Roulette"
    static let description = IntentDescription(
        "Opens Movie Roulette Tuesday, spins the wheel, and saves the movie to your spin history.",
        categoryName: "Roulette"
    )
    static let openAppWhenRun = true
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let spin = try await IntentSpinService.spin()
        let dialog = IntentDialog(stringLiteral: spin.spokenLine)
        return .result(dialog: dialog, view: SpinSnippetView(spin: spin))
    }
}

/// "Open in App" from the snippet: opens the movie's page.
struct OpenSpunMovieIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Movie in Movie Roulette"
    static let openAppWhenRun = true
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }
    static let isDiscoverable = false

    @Parameter(title: "Movie ID")
    var movieID: String

    init() {}
    init(movieID: String) { self.movieID = movieID }

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRuntime.router().open(.movie(id: movieID))
        return .result()
    }
}

struct MovieRouletteShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SpinMovieRouletteIntent(),
            phrases: [
                "Spin \(.applicationName)",
                "Spin the wheel in \(.applicationName)",
                "What should we watch with \(.applicationName)",
            ],
            shortTitle: "Spin the Wheel",
            systemImageName: "dial.medium"
        )
        AppShortcut(
            intent: OpenMovieIntent(),
            phrases: [
                "Open \(\.$movie) in \(.applicationName)",
            ],
            shortTitle: "Open Movie",
            systemImageName: "film"
        )
        AppShortcut(
            intent: LatestEpisodeIntent(),
            phrases: [
                "Latest episode of \(.applicationName)",
                "What's the latest \(.applicationName) episode",
            ],
            shortTitle: "Latest Episode",
            systemImageName: "mic"
        )
        AppShortcut(
            intent: ShowWatchlistIntent(),
            phrases: [
                "What's on my \(.applicationName) watchlist",
                "Show my \(.applicationName) watchlist",
            ],
            shortTitle: "Show Watchlist",
            systemImageName: "bookmark"
        )
        AppShortcut(
            intent: AddToWatchlistIntent(),
            phrases: [
                "Add \(\.$movie) to my \(.applicationName) watchlist",
            ],
            shortTitle: "Add to Watchlist",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: MarkWatchedIntent(),
            phrases: [
                "Mark \(\.$movie) as watched in \(.applicationName)",
            ],
            shortTitle: "Mark Watched",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: WhereToWatchIntent(),
            phrases: [
                "Where can I watch \(\.$movie) in \(.applicationName)",
            ],
            shortTitle: "Where to Watch",
            systemImageName: "tv"
        )
        AppShortcut(
            intent: OpenOnProviderIntent(),
            phrases: [
                // App Shortcut phrases may name only one parameter. The intent
                // still takes movie and service; Siri asks for the other one.
                "Open \(\.$movie) on a service in \(.applicationName)",
                "Open a movie on \(\.$provider) in \(.applicationName)",
            ],
            shortTitle: "Open on Provider",
            systemImageName: "arrow.up.right.square"
        )
        AppShortcut(
            intent: WhatShouldIWatchIntent(),
            phrases: [
                "What should I watch in \(.applicationName)",
            ],
            shortTitle: "What Should I Watch",
            systemImageName: "sparkles"
        )
    }
    static let shortcutTileColor: ShortcutTileColor = .teal
}

// MARK: - Spin

struct IntentSpin: Equatable, Sendable {
    let movie: Movie
    let category: RouletteCategory
    let discussed: String
    let isJackpot: Bool

    var spokenLine: String {
        let prefix = isJackpot ? "Infamous Jackpot! " : ""
        return "\(prefix)The wheel landed on \(category.displayName): \(movie.title), from \(movie.year)."
    }
}

enum IntentSpinError: Error, CustomLocalizedStringResourceConvertible {
    case noMovies
    var localizedStringResource: LocalizedStringResource {
        "The movie list couldn’t be loaded. Open Movie Roulette Tuesday and try again."
    }
}

@MainActor
enum IntentSpinService {
    struct Produced: Sendable {
        var spin: IntentSpin
        var pending: PendingSpin
    }

    static func spin() async throws -> IntentSpin {
        let catalog = try await IntentCatalog.load()
        let history = IntentRuntime.history()
        let averages = ListenerRatingsSnapshot.load(from: IntentRuntime.defaults())?.averages ?? [:]
        var rng = SystemRandomNumberGenerator()
        let produced = try resolveAndRecord(catalog: catalog, history: history, averages: averages, using: &rng)
        IntentRuntime.router().handOffSpin(produced.pending)
        return produced.spin
    }

    /// One pick, one history row, one pending spin for the wheel. Does not
    /// animate. `publishWidget` is false in tests.
    static func resolveAndRecord<G: RandomNumberGenerator>(
        catalog: MovieCatalog,
        history: SpinHistoryStore,
        averages: [String: Double] = [:],
        episodesByGUID: [String: PodcastEpisode] = [:],
        using rng: inout G,
        now: Date = Date(),
        publishWidget: Bool = true
    ) throws -> Produced {
        let policy = RareOutcomePolicy(isEnabled: true)
        guard let out = QuickSpin.resolve(
            catalog: catalog, history: history.results, rareOutcomes: policy,
            listenerAverages: averages, using: &rng
        ) else {
            throw IntentSpinError.noMovies
        }
        let result = SpinResult(movieId: out.movie.id, categoryId: out.category.id, timestamp: now)
        history.record(result)
        if publishWidget {
            WidgetBridge.publishSpin(movie: out.movie, category: out.category, at: result.timestamp)
        }
        let spin = IntentSpin(
            movie: out.movie,
            category: out.category,
            discussed: EpisodeLabel.discussedText(for: out.movie, episodesByGUID: episodesByGUID),
            isJackpot: out.isJackpot
        )
        let pending = PendingSpin(
            movieID: out.movie.id,
            landedCategoryID: out.landed.id,
            creditedCategoryID: out.category.id,
            isJackpot: out.isJackpot,
            resultID: result.id
        )
        return Produced(spin: spin, pending: pending)
    }
}

// MARK: - Snippet (matches the approved v4 mockup)

struct SpinSnippetView: View {
    let spin: IntentSpin

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                FilmBadge(size: 26)
                Text("MOVIE ROULETTE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
            }
            HStack(alignment: .center, spacing: 14) {
                Image("roulette.wheel").resizable().scaledToFit().frame(width: 54, height: 54)
                    .foregroundStyle(Brand.teal)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(spin.isJackpot ? "INFAMOUS JACKPOT · \(spin.category.name.uppercased())" : spin.category.name.uppercased())
                        .font(.caption2.weight(.heavy))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color(hex: spin.category.displayHex), in: Capsule())
                        .foregroundStyle(Color.labelColor(onHex: spin.category.displayHex))
                    Text(spin.movie.title).font(.title3.bold()).lineLimit(2)
                    Text("\(String(spin.movie.year)) · \(spin.movie.genre) · \(spin.discussed)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            HStack(spacing: 10) {
                Button(intent: SpinMovieRouletteIntent()) {
                    Text("Spin Again").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(Brand.teal.opacity(0.18), in: Capsule()).foregroundStyle(Brand.teal)
                }
                .buttonStyle(.plain)
                Button(intent: OpenSpunMovieIntent(movieID: spin.movie.id)) {
                    Text("Open in App").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(Color.primary.opacity(0.08), in: Capsule()).foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
            Text("Saved to your spin history.").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(18)
    }
}
