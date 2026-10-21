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

/// Half-star ratings: 1...10 half-stars (0.5...5 stars). Older data stored
/// whole stars 1...5; those read as stars × 2. Pure, so it's testable.
public enum HalfStars {
    public static let range = 1...10

    /// Out-of-range values are clamped; 0, negative or nil clears.
    public static func clamped(_ halfStars: Int?) -> Int? {
        guard let halfStars, halfStars > 0 else { return nil }
        return min(max(halfStars, range.lowerBound), range.upperBound)
    }

    /// A legacy whole-star value (1...5) as half-stars.
    public static func fromLegacyStars(_ stars: Int?) -> Int? {
        PersonalRatings.clampedRating(stars).map { $0 * 2 }
    }

    /// New field first, else the legacy whole-star field × 2.
    public static func resolved(halfStars: Int?, legacyStars: Int?) -> Int? {
        clamped(halfStars) ?? fromLegacyStars(legacyStars)
    }

    /// Whole stars for older readers: 3.5 -> 4, 0.5 -> 1 (never 0).
    public static func roundedStars(_ halfStars: Int) -> Int {
        let h = clamped(halfStars) ?? 1
        return min(max((h + 1) / 2, 1), 5)
    }

    public static func stars(_ halfStars: Int) -> Double { Double(halfStars) / 2 }

    /// An average in stars, shown with half-star precision (4.26 -> 4.5).
    public static func roundedToHalf(_ stars: Double) -> Double {
        guard stars.isFinite else { return 0 }
        return (stars * 2).rounded(.toNearestOrAwayFromZero) / 2
    }

    /// "3.5", "4".
    public static func label(_ halfStars: Int) -> String {
        halfStars % 2 == 0 ? "\(halfStars / 2)" : "\(halfStars / 2).5"
    }

    /// "4.5" / "4" for a star value already rounded to halves.
    public static func label(stars: Double) -> String {
        label(Int((roundedToHalf(stars) * 2).rounded()))
    }

    /// A touch at `x` along a row of 5 stars `width` wide: the left half of a
    /// star gives .5, the right half the whole star. Always 1...10.
    public static func fromLocation(_ x: Double, width: Double) -> Int {
        guard width > 0, x.isFinite else { return 1 }
        let f = min(max(x / width, 0), 1)
        return clamped(Int((f * 10).rounded(.up))) ?? 1
    }

    /// How full star `index` (1...5) is: 0, 0.5 or 1.
    public static func fill(star index: Int, halfStars: Int?) -> Double {
        let h = halfStars ?? 0
        if h >= index * 2 { return 1 }
        if h == index * 2 - 1 { return 0.5 }
        return 0
    }

    /// VoiceOver adjustable action: ±0.5 star; decrementing below 0.5 clears.
    public static func adjusted(_ halfStars: Int?, increment: Bool) -> Int? {
        let h = halfStars ?? 0
        return increment ? min(h + 1, range.upperBound) : (h <= 1 ? nil : h - 1)
    }
}

/// Your own take on one movie. Stored only on this device.
public struct PersonalMovieEntry: Codable, Equatable, Sendable {
    /// 1...10 half-stars, or nil when unrated.
    public var halfStars: Int?
    public var status: WatchStatus?
    public var updatedAt: Date

    /// Whole stars 1...5 (rounded) for older code paths; setting it stores stars × 2.
    public var rating: Int? {
        get { halfStars.map(HalfStars.roundedStars) }
        set { halfStars = HalfStars.fromLegacyStars(newValue) }
    }

    public init(rating: Int? = nil, status: WatchStatus? = nil, updatedAt: Date = Date()) {
        self.halfStars = HalfStars.fromLegacyStars(rating)
        self.status = status
        self.updatedAt = updatedAt
    }

    public init(halfStars: Int?, status: WatchStatus? = nil, updatedAt: Date = Date()) {
        self.halfStars = HalfStars.clamped(halfStars)
        self.status = status
        self.updatedAt = updatedAt
    }

    public var isEmpty: Bool { halfStars == nil && status == nil }

    private enum CodingKeys: String, CodingKey { case rating, halfStars, status, updatedAt }

    /// Tolerant decoding for older/newer files: an unknown status, an
    /// out-of-range or wrongly typed rating, or a missing date never fails
    /// the whole file. Files from before half-stars only have `rating`
    /// (whole stars), read as stars × 2.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        halfStars = HalfStars.resolved(
            halfStars: (try? c.decodeIfPresent(Int.self, forKey: .halfStars)) ?? nil,
            legacyStars: (try? c.decodeIfPresent(Int.self, forKey: .rating)) ?? nil
        )
        status = ((try? c.decodeIfPresent(String.self, forKey: .status)) ?? nil).flatMap(WatchStatus.init(rawValue:))
        updatedAt = ((try? c.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? nil) ?? .distantPast
    }

    /// Writes both `halfStars` and the rounded `rating`, so a downgrade still reads it.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(halfStars, forKey: .halfStars)
        try c.encodeIfPresent(rating, forKey: .rating)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encode(updatedAt, forKey: .updatedAt)
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
    public func halfStars(for movieId: String) -> Int? { entries[movieId]?.halfStars }
    public func status(for movieId: String) -> WatchStatus? { entries[movieId]?.status }

    public mutating func setRating(_ rating: Int?, for movieId: String, now: Date = Date()) {
        setHalfStars(HalfStars.fromLegacyStars(rating), for: movieId, now: now)
    }

    public mutating func setHalfStars(_ halfStars: Int?, for movieId: String, now: Date = Date()) {
        var entry = entries[movieId] ?? PersonalMovieEntry(updatedAt: now)
        entry.halfStars = HalfStars.clamped(halfStars)
        // Rating a movie implies you've seen it.
        if entry.halfStars != nil, entry.status == nil || entry.status == .wantToWatch { entry.status = .watched }
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
        public var halfStars: Int
        /// Rounded whole stars.
        public var stars: Int { HalfStars.roundedStars(halfStars) }
    }

    public struct VersusHosts: Equatable, Sendable {
        public var movieId: String
        public var title: String
        public var yourHalfStars: Int
        public var yourStars: Double { HalfStars.stars(yourHalfStars) }
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
        let you = versusHosts.map(\.yourStars).reduce(0, +)
        let hosts = versusHosts.map(\.hostRating).reduce(0, +)
        return (you - hosts) / Double(versusHosts.count)
    }

    public init(ratings: PersonalRatings, catalog: MovieCatalog?, topLimit: Int = 5) {
        let rated = ratings.entries.compactMap { id, entry -> Rated? in
            guard let half = entry.halfStars else { return nil }
            // Ratings for movies no longer in the catalog are still counted.
            return Rated(movieId: id, title: catalog?.movie(withId: id)?.title ?? id, halfStars: half)
        }
        ratedCount = rated.count
        averageStars = rated.isEmpty ? nil : Double(rated.map(\.halfStars).reduce(0, +)) / 2 / Double(rated.count)
        topRated = Array(rated.sorted {
            $0.halfStars != $1.halfStars ? $0.halfStars > $1.halfStars
                : $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }.prefix(max(0, topLimit)))
        versusHosts = rated.compactMap { r in
            guard let host = catalog?.movie(withId: r.movieId)?.hostRating, host.isFinite else { return nil }
            return VersusHosts(movieId: r.movieId, title: r.title, yourHalfStars: r.halfStars, hostRating: host)
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
        case .notSpunYet: return "Not spun yet"
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
