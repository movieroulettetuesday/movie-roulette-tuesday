import AppIntents
import SwiftUI
import MRTCore
import MRTShared

/// "Hey Siri, spin Movie Roulette": a real spin (same geometry, rare outcomes
/// and movie selector as the wheel, via `QuickSpin`), recorded to the same
/// spin history the app shows. App Intents run in the app's own process, and
/// `SpinHistoryStore.shared` is the instance the UI uses, so a spin from Siri
/// shows up immediately if the app is open and is persisted to the app's
/// Application Support file if it isn't.
struct SpinMovieRouletteIntent: AppIntent {
    static let title: LocalizedStringResource = "Spin Movie Roulette"
    static let description = IntentDescription(
        "Spins the wheel, picks a movie and saves it to your spin history.",
        categoryName: "Roulette"
    )
    static let openAppWhenRun = false

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
    static let isDiscoverable = false

    @Parameter(title: "Movie ID")
    var movieID: String

    init() {}
    init(movieID: String) { self.movieID = movieID }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.open(.movie(id: movieID))
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
    }
    static let shortcutTileColor: ShortcutTileColor = .teal
}

// MARK: - Spin

struct IntentSpin: Sendable {
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
    static func spin(settings: UserDefaults = .standard) async throws -> IntentSpin {
        let catalog = try await AppCatalog.localSource().loadCatalog().deduplicated()
        let history = SpinHistoryStore.shared
        let policy = RareOutcomePolicy(isEnabled: true)
        var rng = SystemRandomNumberGenerator()
        // Cached listener averages (saved by the app), so a jackpot is weighted offline.
        let averages = ListenerRatingsSnapshot.load(from: settings)?.averages ?? [:]
        guard let out = QuickSpin.resolve(
            catalog: catalog, history: history.results, rareOutcomes: policy,
            listenerAverages: averages, using: &rng
        ) else {
            throw IntentSpinError.noMovies
        }
        let result = SpinResult(movieId: out.movie.id, categoryId: out.category.id)
        history.record(result)
        WidgetBridge.publishSpin(movie: out.movie, category: out.category, at: result.timestamp)
        return IntentSpin(
            movie: out.movie,
            category: out.category,
            discussed: EpisodeLabel.discussedText(for: out.movie),
            isJackpot: out.isJackpot
        )
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
