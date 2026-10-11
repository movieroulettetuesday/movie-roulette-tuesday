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

    /// Fetch, parse and write the cache, all off the main actor.
    @concurrent
    public static func refresh(from url: URL, cacheURL: URL?) async throws -> CachedEpisodeFeed {
        let feed = try await fetchRemote(from: url)
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
        return Snapshot(
            totalSpins: stats.totalSpins,
            distinctMovies: stats.distinctMoviesSpun,
            mostSpunMovie: movieHits.max(by: { $0.value < $1.value }).map { CountedID(id: $0.key, count: $0.value) },
            mostSpunCategory: categoryHits.max(by: { $0.value < $1.value }).map { CountedID(id: $0.key, count: $0.value) },
            categoryBreakdown: categoryHits.sorted { $0.value > $1.value }.map { CountedID(id: $0.key, count: $0.value) },
            genreBreakdown: genreHits.sorted { $0.value > $1.value }.map { CountedGenre(genre: $0.key, count: $0.value) },
            recent: Array(history.suffix(max(0, recentLimit)).reversed())
        )
    }
}
