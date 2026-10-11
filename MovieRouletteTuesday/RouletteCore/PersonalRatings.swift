import Foundation

/// Where a movie sits on your personal list.
public enum WatchStatus: String, Codable, CaseIterable, Sendable {
    case wantToWatch
    case watched

    public var label: String {
        switch self {
        case .wantToWatch: return "Want to watch"
        case .watched: return "Watched"
        }
    }
}

/// Your own take on one movie. Stored only on this device.
public struct PersonalMovieEntry: Codable, Equatable, Sendable {
    /// 1...5 stars, or nil when unrated.
    public var rating: Int?
    public var status: WatchStatus?
    public var updatedAt: Date

    public init(rating: Int? = nil, status: WatchStatus? = nil, updatedAt: Date = Date()) {
        self.rating = PersonalRatings.clampedRating(rating)
        self.status = status
        self.updatedAt = updatedAt
    }

    public var isEmpty: Bool { rating == nil && status == nil }

    private enum CodingKeys: String, CodingKey { case rating, status, updatedAt }

    /// Tolerant decoding for older/newer files: an unknown status, an
    /// out-of-range or wrongly typed rating, or a missing date never fails
    /// the whole file.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rating = PersonalRatings.clampedRating((try? c.decodeIfPresent(Int.self, forKey: .rating)) ?? nil)
        status = ((try? c.decodeIfPresent(String.self, forKey: .status)) ?? nil).flatMap(WatchStatus.init(rawValue:))
        updatedAt = ((try? c.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? nil) ?? .distantPast
    }
}

/// Pure value type holding every personal entry, keyed by movie id.
public struct PersonalRatings: Codable, Equatable, Sendable {
    public static let ratingRange = 1...5

    public private(set) var entries: [String: PersonalMovieEntry]

    public init(entries: [String: PersonalMovieEntry] = [:]) {
        self.entries = entries.filter { !$0.value.isEmpty }
    }

    private enum CodingKeys: String, CodingKey { case entries }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try c.decodeIfPresent([String: PersonalMovieEntry].self, forKey: .entries) ?? [:]
        self.init(entries: decoded)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(entries, forKey: .entries)
    }

    /// Out-of-range values are clamped; 0 or nil clears.
    public static func clampedRating(_ rating: Int?) -> Int? {
        guard let rating, rating > 0 else { return nil }
        return min(max(rating, ratingRange.lowerBound), ratingRange.upperBound)
    }

    public func entry(for movieId: String) -> PersonalMovieEntry? { entries[movieId] }
    public func rating(for movieId: String) -> Int? { entries[movieId]?.rating }
    public func status(for movieId: String) -> WatchStatus? { entries[movieId]?.status }

    public mutating func setRating(_ rating: Int?, for movieId: String, now: Date = Date()) {
        var entry = entries[movieId] ?? PersonalMovieEntry(updatedAt: now)
        entry.rating = Self.clampedRating(rating)
        // Rating a movie implies you've seen it.
        if entry.rating != nil, entry.status == nil || entry.status == .wantToWatch { entry.status = .watched }
        entry.updatedAt = now
        store(entry, for: movieId)
    }

    public mutating func setStatus(_ status: WatchStatus?, for movieId: String, now: Date = Date()) {
        var entry = entries[movieId] ?? PersonalMovieEntry(updatedAt: now)
        entry.status = status
        entry.updatedAt = now
        store(entry, for: movieId)
    }

    private mutating func store(_ entry: PersonalMovieEntry, for movieId: String) {
        entries[movieId] = entry.isEmpty ? nil : entry
    }

    public var watchlist: Set<String> {
        Set(entries.filter { $0.value.status == .wantToWatch }.keys)
    }

    public var watched: Set<String> {
        Set(entries.filter { $0.value.status == .watched }.keys)
    }
}

/// "Your ratings" numbers for the Stats tab.
public struct PersonalRatingsSummary: Equatable, Sendable {
    public struct Rated: Equatable, Sendable {
        public var movieId: String
        public var title: String
        public var stars: Int
    }

    public struct VersusHosts: Equatable, Sendable {
        public var movieId: String
        public var title: String
        public var yourStars: Int
        public var hostRating: Double
    }

    public var ratedCount: Int
    public var averageStars: Double?
    /// Highest-rated first; ties broken by title.
    public var topRated: [Rated]
    /// Only movies that have a `hostRating` AND your rating.
    public var versusHosts: [VersusHosts]
    public var watchlistCount: Int
    public var watchedCount: Int

    /// Your average minus the hosts' average over `versusHosts` (nil when empty).
    public var averageDifferenceFromHosts: Double? {
        guard !versusHosts.isEmpty else { return nil }
        let you = versusHosts.map { Double($0.yourStars) }.reduce(0, +)
        let hosts = versusHosts.map(\.hostRating).reduce(0, +)
        return (you - hosts) / Double(versusHosts.count)
    }

    public init(ratings: PersonalRatings, catalog: MovieCatalog?, topLimit: Int = 5) {
        let rated = ratings.entries.compactMap { id, entry -> Rated? in
            guard let stars = entry.rating else { return nil }
            // Ratings for movies no longer in the catalog are still counted.
            return Rated(movieId: id, title: catalog?.movie(withId: id)?.title ?? id, stars: stars)
        }
        ratedCount = rated.count
        averageStars = rated.isEmpty ? nil : Double(rated.map(\.stars).reduce(0, +)) / Double(rated.count)
        topRated = Array(rated.sorted {
            $0.stars != $1.stars ? $0.stars > $1.stars
                : $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }.prefix(max(0, topLimit)))
        versusHosts = rated.compactMap { r in
            guard let host = catalog?.movie(withId: r.movieId)?.hostRating, host.isFinite else { return nil }
            return VersusHosts(movieId: r.movieId, title: r.title, yourStars: r.stars, hostRating: host)
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        watchlistCount = ratings.watchlist.count
        watchedCount = ratings.watched.count
    }
}

/// JSON file store for personal ratings (Application Support), mirroring `SpinHistoryFileStore`.
public struct PersonalRatingsFileStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    /// `<Application Support>/MovieRoulette/personal-ratings.json`
    public static func applicationSupport(fileManager: FileManager = .default) throws -> PersonalRatingsFileStore {
        let base = try fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return PersonalRatingsFileStore(fileURL: base
            .appendingPathComponent("MovieRoulette", isDirectory: true)
            .appendingPathComponent("personal-ratings.json", isDirectory: false))
    }

    /// Missing file -> empty ratings.
    public func load() throws -> PersonalRatings {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return PersonalRatings() }
        return try JSONDecoder().decode(PersonalRatings.self, from: Data(contentsOf: fileURL))
    }

    public func save(_ ratings: PersonalRatings) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(ratings).write(to: fileURL, options: .atomic)
    }
}

/// Movies-tab list filter (pure, so it's testable).
public enum MovieListFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case watchlist
    case watched
    case rated
    case notSpunYet

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .all: return "All movies"
        case .watchlist: return "Watchlist"
        case .watched: return "Watched"
        case .rated: return "Rated by me"
        case .notSpunYet: return "Haven't spun yet"
        }
    }

    public func apply(to movies: [Movie], ratings: PersonalRatings, spinStats: SpinStats) -> [Movie] {
        switch self {
        case .all: return movies
        case .watchlist: return movies.filter { ratings.status(for: $0.id) == .wantToWatch }
        case .watched: return movies.filter { ratings.status(for: $0.id) == .watched }
        case .rated: return movies.filter { ratings.rating(for: $0.id) != nil }
        case .notSpunYet: return movies.filter { !spinStats.hasBeenSpun(movie: $0.id) }
        }
    }
}
