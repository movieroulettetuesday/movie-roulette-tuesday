import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Pure feed fetch/cache helpers (UI-free). `EpisodeStore` wraps these on the main actor.
public enum EpisodeFeedIO {
    public static let defaultFeedURL = URL(string: "https://rss.buzzsprout.com/2117292.rss")!

    public static func cacheURL(fileManager: FileManager = .default) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return base
            .appendingPathComponent("MovieRoulette", isDirectory: true)
            .appendingPathComponent("episodes-cache.json", isDirectory: false)
    }

    public static func loadCache(from url: URL) throws -> CachedEpisodeFeed {
        try JSONDecoder().decode(CachedEpisodeFeed.self, from: Data(contentsOf: url))
    }

    public static func saveCache(_ cache: CachedEpisodeFeed, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(cache).write(to: url, options: .atomic)
    }

    /// Per-request timeout for the RSS fetch (URLSession's default is 60 s).
    public static let requestTimeout: TimeInterval = 20

    /// Download + parse. `@concurrent` so the XML parse never runs on the
    /// main actor (with approachable concurrency, plain nonisolated async
    /// functions would run on the caller's actor).
    @concurrent
    public static func fetchRemote(
        from url: URL = defaultFeedURL,
        session: URLSession = .shared
    ) async throws -> PodcastFeed {
        let request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: requestTimeout)
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CatalogLoadingError.badHTTPStatus(http.statusCode)
        }
        return try RSSFeedParser.parse(data: data)
    }

    /// A refresh that yields 0 episodes is a failure, never a valid (empty) feed:
    /// any well-formed non-RSS HTTP 200 (captive portal, outage page) or a channel
    /// with no items parses as 0 episodes and must not replace the cached list.
    public static func validated(_ feed: PodcastFeed) throws -> PodcastFeed {
        guard !feed.episodes.isEmpty else { throw RSSFeedError.noEpisodes }
        return feed
    }

    /// Fetch, parse and write the cache, all off the main actor. Throws (and
    /// leaves the cache untouched) when the feed has no episodes.
    @concurrent
    public static func refresh(
        from url: URL, cacheURL: URL?, session: URLSession = .shared
    ) async throws -> CachedEpisodeFeed {
        let feed = try validated(await fetchRemote(from: url, session: session))
        let cached = CachedEpisodeFeed(title: feed.title, episodes: feed.episodes, artworkURL: feed.artworkURL)
        if let cacheURL { try? saveCache(cached, to: cacheURL) }
        return cached
    }

    /// Cache read off the main actor. A missing or unreadable cache is just "no cache".
    @concurrent
    public static func loadCacheIfPresent(from url: URL?) async -> CachedEpisodeFeed? {
        guard let url else { return nil }
        return try? loadCache(from: url)
    }
}

/// On-disk feed cache. Fields added later (`artworkURL`, and `imageURL` on
/// each episode) are optional, so caches from older app versions still load;
/// the next network refresh fills them in.
public struct CachedEpisodeFeed: Codable, Equatable, Sendable {
    public var fetchedAt: Date
    public var title: String
    public var episodes: [PodcastEpisode]
    /// Show (channel) artwork, the fallback when an episode has none.
    public var artworkURL: URL?

    public init(fetchedAt: Date = Date(), title: String, episodes: [PodcastEpisode], artworkURL: URL? = nil) {
        self.fetchedAt = fetchedAt
        self.title = title
        self.episodes = episodes
        self.artworkURL = artworkURL
    }
}

public struct CountedID: Equatable, Sendable {
    public var id: String
    public var count: Int
    public init(id: String, count: Int) {
        self.id = id
        self.count = count
    }
}

public struct CountedGenre: Equatable, Sendable {
    public var genre: String
    public var count: Int
    public init(genre: String, count: Int) {
        self.genre = genre
        self.count = count
    }
}

/// Aggregations for the Stats tab (pure; no SwiftUI).
public enum StatsCalculator {
    public struct Snapshot: Equatable, Sendable {
        public var totalSpins: Int
        public var distinctMovies: Int
        public var mostSpunMovie: CountedID?
        public var mostSpunCategory: CountedID?
        public var categoryBreakdown: [CountedID]
        public var genreBreakdown: [CountedGenre]
        public var recent: [SpinResult]
    }

    /// `archive` carries the counts of older spins that were compacted out of
    /// the detailed history, so totals stay correct after the history cap.
    public static func snapshot(
        history: [SpinResult],
        catalog: MovieCatalog?,
        archive: SpinHistoryArchive = .empty,
        recentLimit: Int = 10
    ) -> Snapshot {
        let stats = SpinStats(history: history, archive: archive)
        var movieHits = archive.movieCounts
        var categoryHits = archive.categoryCounts
        var genreHits: [String: Int] = [:]
        // One lookup table instead of a linear catalog search per spin.
        let genreById = Dictionary(
            (catalog?.movies ?? []).map { ($0.id, $0.genre) }, uniquingKeysWith: { first, _ in first }
        )
        for (movieId, count) in archive.movieCounts {
            if let genre = genreById[movieId] {
                genreHits[genre, default: 0] += count
            }
        }
        for spin in history {
            movieHits[spin.movieId, default: 0] += 1
            categoryHits[spin.categoryId, default: 0] += 1
            if let genre = genreById[spin.movieId] {
                genreHits[genre, default: 0] += 1
            }
        }
        let movies = ranked(movieHits), categories = ranked(categoryHits)
        return Snapshot(
            totalSpins: stats.totalSpins,
            distinctMovies: stats.distinctMoviesSpun,
            mostSpunMovie: movies.first.map { CountedID(id: $0.key, count: $0.count) },
            mostSpunCategory: categories.first.map { CountedID(id: $0.key, count: $0.count) },
            categoryBreakdown: categories.map { CountedID(id: $0.key, count: $0.count) },
            genreBreakdown: ranked(genreHits).map { CountedGenre(genre: $0.key, count: $0.count) },
            recent: Array(history.suffix(max(0, recentLimit)).reversed())
        )
    }

    /// Deterministic order for counts (Dictionary order changes every launch):
    /// count descending, then key (id or genre) ascending by plain Unicode code points.
    /// `mostSpun*` is the first element of this order.
    public static func ranked(_ counts: [String: Int]) -> [(key: String, count: Int)] {
        counts.map { (key: $0.key, count: $0.value) }.sorted { a, b in
            if a.count != b.count { return a.count > b.count }
            return a.key.unicodeScalars.lexicographicallyPrecedes(b.key.unicodeScalars)
        }
    }
}

// MARK: - Episode grouping (Season / Year / All)

public enum EpisodeGrouping: String, CaseIterable, Identifiable, Sendable {
    case season, year, all
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .season: return "Season"
        case .year: return "Year"
        case .all: return "All"
        }
    }
}

public struct EpisodeGroup: Identifiable, Equatable, Sendable {
    /// Stable key for the remembered open/closed state ("season-4", "bonus", "year-2026", "all").
    public let id: String
    public let title: String
    public let episodes: [PodcastEpisode]
}

/// Pure grouping, newest group first. Episodes keep their order inside a group.
/// No season -> "Bonus" (last); by year, every episode goes under its pubDate
/// year (season or not); no date -> "Undated" (last).
public enum EpisodeGrouper {
    public static let bonusID = "bonus"

    public static func groups(_ episodes: [PodcastEpisode], by grouping: EpisodeGrouping,
                              calendar: Calendar = .current) -> [EpisodeGroup] {
        switch grouping {
        case .all:
            return episodes.isEmpty ? [] : [EpisodeGroup(id: "all", title: "All Episodes", episodes: episodes)]
        case .season:
            var bySeason: [Int: [PodcastEpisode]] = [:]
            var bonus: [PodcastEpisode] = []
            for ep in episodes {
                if let s = ep.season { bySeason[s, default: []].append(ep) } else { bonus.append(ep) }
            }
            var out = bySeason.keys.sorted(by: >).map {
                EpisodeGroup(id: "season-\($0)", title: "Season \($0)", episodes: bySeason[$0] ?? [])
            }
            if !bonus.isEmpty { out.append(EpisodeGroup(id: bonusID, title: "Bonus", episodes: bonus)) }
            return out
        case .year:
            var byYear: [Int: [PodcastEpisode]] = [:]
            var undated: [PodcastEpisode] = []
            for ep in episodes {
                if let d = ep.pubDate { byYear[calendar.component(.year, from: d), default: []].append(ep) } else { undated.append(ep) }
            }
            var out = byYear.keys.sorted(by: >).map {
                EpisodeGroup(id: "year-\($0)", title: String($0), episodes: byYear[$0] ?? [])
            }
            if !undated.isEmpty { out.append(EpisodeGroup(id: "undated", title: "Undated", episodes: undated)) }
            return out
        }
    }
}

/// Remembered open/closed headers, stored as one string ("season-4:1,season-3:0").
/// A group with no saved state is open only when it is the newest group.
public struct EpisodeGroupExpansion: Equatable, Sendable {
    public private(set) var states: [String: Bool]

    public init(states: [String: Bool] = [:]) { self.states = states }

    public init(serialized: String) {
        var states: [String: Bool] = [:]
        for part in serialized.split(separator: ",") {
            let kv = part.split(separator: ":")
            guard kv.count == 2, !kv[0].isEmpty else { continue }
            states[String(kv[0])] = kv[1] == "1"
        }
        self.states = states
    }

    public var serialized: String {
        states.keys.sorted().map { "\($0):\(states[$0]! ? 1 : 0)" }.joined(separator: ",")
    }

    public func isExpanded(_ id: String, isNewest: Bool) -> Bool { states[id] ?? isNewest }

    public mutating func toggle(_ id: String, isNewest: Bool) {
        states[id] = !isExpanded(id, isNewest: isNewest)
    }
}
