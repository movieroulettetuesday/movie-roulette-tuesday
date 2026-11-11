import AppIntents
import Foundation
#if canImport(UIKit)
import UIKit
#endif
import MRTCore
import MRTShared

enum IntentError: Error, Equatable, CustomLocalizedStringResourceConvertible {
    case unknownMovie
    case catalogUnavailable
    case noEpisodes
    case noProviderLink

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .unknownMovie:
            "I couldn’t find that movie in Movie Roulette Tuesday."
        case .catalogUnavailable:
            "The movie list couldn’t be loaded. Open Movie Roulette Tuesday and try again."
        case .noEpisodes:
            "There aren’t any saved episodes yet. Open Movie Roulette Tuesday to refresh the show."
        case .noProviderLink:
            "There’s no link for that service."
        }
    }
}

/// What the intents read and write. Tests replace these; the app uses the
/// shared stores, so a Siri change is the same file the screen is showing.
@MainActor
enum IntentRuntime {
    /// When false, intents set the route and skip the system "bring the app
    /// forward" call. Unit tests set this so they don't need an intent session.
    static var opensApp = true
    static var catalog: () async throws -> MovieCatalog = defaultCatalog
    static var ratings: () -> PersonalRatingsStore = { .shared }
    static var history: () -> SpinHistoryStore = { .shared }
    static var router: () -> AppRouter = { .shared }
    static var episodes: () -> [PodcastEpisode] = { EpisodeCacheReader.cachedEpisodes() }
    static var appleTrackIDs: () -> [String: Int] = { AppleEpisodeLinks.shared.trackIDs }
    static var defaults: () -> UserDefaults = { .standard }
    static var canOpenURL: (URL) -> Bool = defaultCanOpen
    static var openURL: (URL) async -> Bool = defaultOpen

    static func reset() {
        opensApp = true
        catalog = defaultCatalog
        ratings = { .shared }
        history = { .shared }
        router = { .shared }
        episodes = { EpisodeCacheReader.cachedEpisodes() }
        appleTrackIDs = { AppleEpisodeLinks.shared.trackIDs }
        defaults = { .standard }
        canOpenURL = defaultCanOpen
        openURL = defaultOpen
    }

    private static func defaultCatalog() async throws -> MovieCatalog {
        try await AppCatalog.localSource().loadCatalog().deduplicated()
    }

    private static func defaultCanOpen(_ url: URL) -> Bool {
        #if os(iOS) || os(tvOS)
        UIApplication.shared.canOpenURL(url)
        #else
        return false
        #endif
    }

    private static func defaultOpen(_ url: URL) async -> Bool {
        #if os(iOS) || os(tvOS)
        await withCheckedContinuation { continuation in
            UIApplication.shared.open(url, options: [:]) { accepted in
                continuation.resume(returning: accepted)
            }
        }
        #else
        return false
        #endif
    }
}

enum IntentCatalog {
    @MainActor
    static func load() async throws -> MovieCatalog {
        do {
            let catalog = try await IntentRuntime.catalog()
            guard !catalog.movies.isEmpty, !catalog.categories.isEmpty else {
                throw IntentError.catalogUnavailable
            }
            return catalog
        } catch let error as IntentError {
            throw error
        } catch {
            throw IntentError.catalogUnavailable
        }
    }

    static func movie(_ id: String, in catalog: MovieCatalog) throws -> Movie {
        guard let movie = catalog.movie(withId: id) else { throw IntentError.unknownMovie }
        return movie
    }
}

// MARK: - Watchlist

enum WatchlistReading {
    static func wantToWatch(in ratings: PersonalRatings, catalog: MovieCatalog) -> [Movie] {
        catalog.movies
            .filter { ratings.status(for: $0.id) == .wantToWatch }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    static func speech(for movies: [Movie]) -> String {
        guard !movies.isEmpty else { return "Your watchlist is empty." }
        let names = movies.prefix(12).map { "\($0.title) (\($0.year))" }
        let extra = movies.count - names.count
        var line = "You want to watch \(spokenAnd(Array(names)))"
        if extra > 0 { line += ", and \(extra) more" }
        return line + "."
    }
}

enum WatchlistEditing {
    /// Sets Want to watch. Does not read or write the star rating.
    static func add(movieID: String, ratings: inout PersonalRatings, now: Date = Date()) {
        ratings.setStatus(.wantToWatch, for: movieID, now: now)
    }

    /// Sets Watched, which takes the movie off Want to watch. Does not invent a rating.
    static func markWatched(movieID: String, ratings: inout PersonalRatings, now: Date = Date()) {
        ratings.setStatus(.watched, for: movieID, now: now)
    }

    static func addSpeech(movie: Movie, alreadyOnList: Bool) -> String {
        alreadyOnList
            ? "\(movie.title) is already on your watchlist."
            : "Added \(movie.title) to your watchlist."
    }

    static func watchedSpeech(movie: Movie) -> String {
        "Marked \(movie.title) as watched."
    }
}

// MARK: - Where to watch

struct WhereToWatchLine: Equatable, Sendable {
    var spoken: String
    var providerNames: [String]
}

enum WhereToWatchSpeech {
    /// Speaks `WhereToWatchDisplay`'s providers. When My Services is set, those
    /// matches are named first; the rest of the public list still follows.
    static func line(for movie: Movie, services: MyServices) -> WhereToWatchLine {
        let display = WhereToWatchDisplay(movie: movie)
        guard display.showsProviders, let streaming = movie.streaming else {
            return WhereToWatchLine(spoken: "\(movie.title): \(WhereToWatchDisplay.emptyMessage)", providerNames: [])
        }
        let mine = StreamingCatalog.matchingServices(movie, services: services)
        let stream = StreamingCatalog.collapsingParamountPlusDuplicates(streaming.stream)
        let free = StreamingCatalog.collapsingParamountPlusDuplicates(streaming.free)
        let rent = StreamingCatalog.collapsingParamountPlusDuplicates(StreamingCatalog.rentOrBuy(streaming))

        var ordered: [StreamingInfo.Provider] = []
        func append(_ providers: [StreamingInfo.Provider]) {
            for provider in providers where !ordered.contains(where: { $0.id == provider.id }) {
                ordered.append(provider)
            }
        }
        if services.isEmpty {
            append(stream)
            append(free)
            append(rent)
        } else {
            append(mine)
            append(stream.filter { !services.contains($0.id) })
            append(free.filter { !services.contains($0.id) })
            append(rent.filter { !services.contains($0.id) })
        }
        let names = ordered.map(\.name)
        guard !names.isEmpty else {
            return WhereToWatchLine(spoken: "\(movie.title): \(WhereToWatchDisplay.emptyMessage)", providerNames: [])
        }
        return WhereToWatchLine(spoken: sentence(movie: movie, names: names, mine: mine, services: services), providerNames: names)
    }

    private static func sentence(movie: Movie, names: [String], mine: [StreamingInfo.Provider], services: MyServices) -> String {
        let spokenNames = Array(names.prefix(8))
        let list = spokenAnd(spokenNames)
        let extra = names.count - spokenNames.count
        let more = extra > 0 ? ", and \(extra) more" : ""
        if !services.isEmpty, !mine.isEmpty {
            let mineNames = mine.map(\.name)
            let verb = mine.count == 1 ? "is one of your services" : "are your services"
            let rest = spokenNames.filter { !mineNames.contains($0) }
            if rest.isEmpty {
                return "\(movie.title) is on \(spokenAnd(mineNames)), which \(verb)\(more)."
            }
            return "\(movie.title) is on \(spokenAnd(mineNames)), which \(verb). Also on \(spokenAnd(rest))\(more)."
        }
        if !services.isEmpty {
            return "\(movie.title) isn’t on your services. It’s on \(list)\(more)."
        }
        return "You can watch \(movie.title) on \(list)\(more)."
    }
}

func spokenAnd(_ names: [String]) -> String {
    switch names.count {
    case 0: return ""
    case 1: return names[0]
    case 2: return "\(names[0]) and \(names[1])"
    default:
        return names.dropLast().joined(separator: ", ") + ", and " + names[names.count - 1]
    }
}

// MARK: - Latest episode

enum LatestEpisodeFailure: Error, Equatable {
    case emptyCache
}

struct LatestEpisodePick: Equatable, Sendable {
    var episode: PodcastEpisode
    var speech: String
    var listenURL: URL?
    var isExactEpisode: Bool
}

enum LatestEpisodeLogic {
    static let emptySpeech = "There aren’t any saved episodes yet. Open Movie Roulette Tuesday to refresh the show."

    static func pick(episodes: [PodcastEpisode], trackIDs: [String: Int], show: ShowInfo = .mrt) throws -> LatestEpisodePick {
        guard let latest = WidgetSnapshot.latest(in: episodes) else { throw LatestEpisodeFailure.emptyCache }
        let link = AppleEpisodeLookup.link(forGUID: latest.guid, in: trackIDs, show: show)
        return LatestEpisodePick(
            episode: latest,
            speech: speech(for: latest),
            listenURL: link?.url,
            isExactEpisode: link?.isExactEpisode ?? false
        )
    }

    static func speech(for episode: PodcastEpisode) -> String {
        var line = "The latest episode is \(episode.title)"
        if let label = episode.seasonEpisodeLabel { line += " (\(label))" }
        if let date = episode.pubDate {
            line += ", \(date.formatted(date: .long, time: .omitted))"
        }
        return line + "."
    }
}

// MARK: - Open on a provider

enum ProviderOpenPlan {
    struct Choice: Equatable, Sendable {
        var destination: ProviderLaunching.Destination
        var urls: [URL]
    }

    /// The same destination a tap on the movie page builds. A movie with no
    /// streaming row still gets that provider's search URL.
    static func choice(for option: StreamingProviderOption, movie: Movie, canOpen: (URL) -> Bool) -> Choice {
        let listed = (movie.streaming.map { $0.stream + $0.free + $0.rent + $0.buy } ?? [])
            .first { option.matches($0) }
        let destination = ProviderLaunching.destination(for: listed ?? option.syntheticProvider, movie: movie)
        return Choice(destination: destination, urls: destination.attempts(canOpen: canOpen))
    }
}

@MainActor
enum ProviderOpening {
    /// `openFirst` stops after one URL. Cancel does not open the next link.
    static func openFirst(_ urls: [URL]) async -> ProviderLaunching.OpenResult {
        await withCheckedContinuation { continuation in
            ProviderLaunching.openFirst(of: urls, using: { url, finish in
                Task { @MainActor in
                    let accepted = await IntentRuntime.openURL(url)
                    finish(accepted)
                }
            }, completion: { result in
                continuation.resume(returning: result)
            })
        }
    }
}
