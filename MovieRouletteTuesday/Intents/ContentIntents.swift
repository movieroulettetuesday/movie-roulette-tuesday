import AppIntents
import SwiftUI

// MARK: - Open Movie

struct OpenMovieIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Movie"
    static let description = IntentDescription(
        "Opens a movie in Movie Roulette Tuesday.",
        categoryName: "Movies"
    )
    static let openAppWhenRun = true
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @Parameter(title: "Movie")
    var movie: MovieEntity = .placeholder

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$movie)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let catalog = try await IntentCatalog.load()
        let movie = try IntentCatalog.movie(self.movie.id, in: catalog)
        IntentRuntime.router().open(.movie(id: movie.id))
        return .result(dialog: IntentDialog(stringLiteral: "Opening \(movie.title)."))
    }
}

// MARK: - Latest episode

struct LatestEpisodeIntent: ForegroundContinuableIntent {
    static let title: LocalizedStringResource = "Latest Episode"
    static let description = IntentDescription(
        "Opens the newest episode and offers to listen in Apple Podcasts.",
        categoryName: "Episodes"
    )
    /// The episode page opens only when the cache has one. An empty cache
    /// stays here and offers an Open button instead.
    static let openAppWhenRun = false
    static var supportedModes: IntentModes { .foreground(.dynamic) }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        do {
            let pick = try LatestEpisodeLogic.pick(
                episodes: IntentRuntime.episodes(),
                trackIDs: IntentRuntime.appleTrackIDs()
            )
            let link = DeepLink.episode(guid: pick.episode.guid)
            IntentRuntime.router().open(link)
            if IntentRuntime.opensApp {
                await comeForward()
            }
            return .result(
                dialog: IntentDialog(stringLiteral: pick.speech),
                view: LatestEpisodeSnippet(pick: pick)
            )
        } catch is LatestEpisodeFailure {
            return .result(
                dialog: IntentDialog(stringLiteral: LatestEpisodeLogic.emptySpeech),
                view: LatestEpisodeOfferView()
            )
        }
    }

    /// iOS 26 uses `continueInForeground`. Earlier systems use the
    /// foreground-continuable request. A refusal still leaves the route set.
    @MainActor
    private func comeForward() async {
        if #available(iOS 26.0, *) {
            try? await continueInForeground(alwaysConfirm: false)
        } else {
            try? await requestToContinueInForeground()
        }
    }
}

/// Hidden. The empty-cache snippet's button.
struct OpenEpisodesTabIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Movie Roulette"
    static let openAppWhenRun = true
    static var supportedModes: IntentModes { .foreground(.immediate) }
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRuntime.router().open(.episodes)
        return .result()
    }
}

/// Hidden. The latest-episode snippet's "Listen in Apple Podcasts" button.
/// Uses the cached iTunes lookup: the exact episode when the GUID is known,
/// otherwise the show page.
struct ListenInApplePodcastsIntent: AppIntent {
    static let title: LocalizedStringResource = "Listen in Apple Podcasts"
    static let openAppWhenRun = true
    static var supportedModes: IntentModes { .foreground(.immediate) }
    static let isDiscoverable = false

    @Parameter(title: "Episode")
    var episodeGUID: String

    init() { episodeGUID = "" }
    init(episodeGUID: String) { self.episodeGUID = episodeGUID }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let link = AppleEpisodeLookup.link(forGUID: episodeGUID, in: IntentRuntime.appleTrackIDs())
        guard let url = link?.url else { throw IntentError.noProviderLink }
        let accepted = await IntentRuntime.openURL(url)
        let which = (link?.isExactEpisode ?? false) ? "that episode" : "the show"
        let speech = accepted ? "Opening \(which) in Apple Podcasts." : "Couldn’t open Apple Podcasts."
        return .result(dialog: IntentDialog(stringLiteral: speech))
    }
}

private struct LatestEpisodeSnippet: View {
    let pick: LatestEpisodePick

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LATEST EPISODE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(pick.episode.title).font(.headline)
            if let label = pick.episode.seasonEpisodeLabel {
                Text(label).font(.subheadline).foregroundStyle(.secondary)
            }
            if let date = pick.episode.pubDate {
                Text(date.formatted(date: .long, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if pick.listenURL != nil {
                Button(intent: ListenInApplePodcastsIntent(episodeGUID: pick.episode.guid)) {
                    Text("Listen in Apple Podcasts")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Brand.teal.opacity(0.18), in: Capsule())
                        .foregroundStyle(Brand.teal)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LatestEpisodeOfferView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No saved episodes yet.").font(.headline)
            Text("Open the app to refresh the show.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(intent: OpenEpisodesTabIntent()) {
                Text("Open Movie Roulette")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Brand.teal.opacity(0.18), in: Capsule())
                    .foregroundStyle(Brand.teal)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Watchlist

struct ShowWatchlistIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Watchlist"
    static let description = IntentDescription(
        "Lists movies you marked Want to watch.",
        categoryName: "Watchlist"
    )
    static let openAppWhenRun = false
    static var supportedModes: IntentModes { .background }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let catalog = try await IntentCatalog.load()
        let movies = WatchlistReading.wantToWatch(in: IntentRuntime.ratings().ratings, catalog: catalog)
        return .result(
            dialog: IntentDialog(stringLiteral: WatchlistReading.speech(for: movies)),
            view: WatchlistSnippetView(movies: movies)
        )
    }
}

struct AddToWatchlistIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to Watchlist"
    static let description = IntentDescription(
        "Marks a movie as Want to watch. Does not change your rating.",
        categoryName: "Watchlist"
    )
    static let openAppWhenRun = false
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Movie")
    var movie: MovieEntity = .placeholder

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$movie) to my watchlist")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let catalog = try await IntentCatalog.load()
        let movie = try IntentCatalog.movie(self.movie.id, in: catalog)
        let store = IntentRuntime.ratings()
        let already = store.status(for: movie.id) == .wantToWatch
        store.edit { ratings in
            WatchlistEditing.add(movieID: movie.id, ratings: &ratings)
        }
        return .result(dialog: IntentDialog(stringLiteral: WatchlistEditing.addSpeech(movie: movie, alreadyOnList: already)))
    }
}

struct MarkWatchedIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark Watched"
    static let description = IntentDescription(
        "Marks a movie as watched. Does not add a star rating.",
        categoryName: "Watchlist"
    )
    static let openAppWhenRun = false
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Movie")
    var movie: MovieEntity = .placeholder

    static var parameterSummary: some ParameterSummary {
        Summary("Mark \(\.$movie) as watched")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let catalog = try await IntentCatalog.load()
        let movie = try IntentCatalog.movie(self.movie.id, in: catalog)
        IntentRuntime.ratings().edit { ratings in
            WatchlistEditing.markWatched(movieID: movie.id, ratings: &ratings)
        }
        return .result(dialog: IntentDialog(stringLiteral: WatchlistEditing.watchedSpeech(movie: movie)))
    }
}

private struct WatchlistSnippetView: View {
    let movies: [Movie]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WANT TO WATCH").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if movies.isEmpty {
                Text("Nothing saved yet.")
            } else {
                ForEach(Array(movies.prefix(8))) { movie in
                    Text("\(movie.title)  ·  \(String(movie.year))")
                        .font(.subheadline.weight(.semibold))
                }
                if movies.count > 8 {
                    Text("And \(movies.count - 8) more").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Where to watch

struct WhereToWatchIntent: AppIntent {
    static let title: LocalizedStringResource = "Where to Watch"
    static let description = IntentDescription(
        "Says where a movie is streaming, your services first.",
        categoryName: "Movies"
    )
    static let openAppWhenRun = false
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Movie")
    var movie: MovieEntity = .placeholder

    static var parameterSummary: some ParameterSummary {
        Summary("Where to watch \(\.$movie)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let catalog = try await IntentCatalog.load()
        let movie = try IntentCatalog.movie(self.movie.id, in: catalog)
        let services = MyServices(serialized: IntentRuntime.defaults().string(forKey: MyServices.storageKey) ?? "")
        let line = WhereToWatchSpeech.line(for: movie, services: services)
        return .result(
            dialog: IntentDialog(stringLiteral: line.spoken),
            view: WhereToWatchSnippetView(title: movie.title, names: line.providerNames)
        )
    }
}

struct OpenOnProviderIntent: AppIntent {
    static let title: LocalizedStringResource = "Open on Provider"
    static let description = IntentDescription(
        "Opens a movie in a streaming app, or on the web if that app isn’t installed.",
        categoryName: "Movies"
    )
    static let openAppWhenRun = true
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @Parameter(title: "Movie")
    var movie: MovieEntity = .placeholder

    @Parameter(title: "Service")
    var provider: StreamingProviderOption = .netflix

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$movie) on \(\.$provider)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let catalog = try await IntentCatalog.load()
        let movie = try IntentCatalog.movie(self.movie.id, in: catalog)
        let choice = ProviderOpenPlan.choice(for: provider, movie: movie, canOpen: IntentRuntime.canOpenURL)
        guard !choice.urls.isEmpty else { throw IntentError.noProviderLink }
        let result = await ProviderOpening.openFirst(choice.urls)
        switch result {
        case .opened(let url):
            let native = choice.destination.appURL == url
            let whereText = native ? choice.destination.appName : "\(choice.destination.appName) on the web"
            return .result(dialog: IntentDialog(stringLiteral: "Opening \(movie.title) on \(whereText)."))
        case .declined:
            return .result(dialog: IntentDialog(stringLiteral: "Couldn’t open \(choice.destination.appName)."))
        case .none:
            throw IntentError.noProviderLink
        }
    }
}

private struct WhereToWatchSnippetView: View {
    let title: String
    let names: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            if names.isEmpty {
                Text(WhereToWatchDisplay.emptyMessage).foregroundStyle(.secondary)
            } else {
                ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                    Text(name).font(.subheadline)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
