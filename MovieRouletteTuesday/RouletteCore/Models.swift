import Foundation

/// Podcast / show metadata bundled with the catalog (deep links, RSS).
public struct ShowInfo: Codable, Hashable, Sendable {
    public var name: String
    public var hosts: [String]
    public var rssURL: URL?
    public var applePodcastsURL: URL?
    public var spotifyURL: URL?
    public var applePodcastID: String?
    public var spotifyShowID: String?
    public var buzzsproutShowID: String?

    public init(
        name: String = "Movie Roulette Tuesday: The Podcast",
        hosts: [String] = ["Rachael", "Karl", "Matt"],
        rssURL: URL? = URL(string: "https://rss.buzzsprout.com/2117292.rss"),
        applePodcastsURL: URL? = URL(string: "https://podcasts.apple.com/us/podcast/movie-roulette-tuesday-the-podcast/id1666123849"),
        spotifyURL: URL? = URL(string: "https://open.spotify.com/show/0jJt5G1XRlbLYWJuyIQnj1"),
        applePodcastID: String? = "1666123849",
        spotifyShowID: String? = "0jJt5G1XRlbLYWJuyIQnj1",
        buzzsproutShowID: String? = "2117292"
    ) {
        self.name = name
        self.hosts = hosts
        self.rssURL = rssURL
        self.applePodcastsURL = applePodcastsURL
        self.spotifyURL = spotifyURL
        self.applePodcastID = applePodcastID
        self.spotifyShowID = spotifyShowID
        self.buzzsproutShowID = buzzsproutShowID
    }

    public static let mrt = ShowInfo()
}

/// A movie that can come up on the wheel.
///
/// Per-device state such as "how many times has this been spun" is deliberately
/// *not* stored here; derive it from spin history (see `SpinStats`).
public struct Movie: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public var title: String
    public var year: Int
    public var genre: String
    /// Ids of the `RouletteCategory` values this movie belongs to.
    public var categories: [String]
    /// Buzzsprout RSS item guids (e.g. "Buzzsprout-19913482").
    public var episodeIds: [String]
    /// Offline-friendly title of the primary episode that discussed this film.
    public var episodeTitle: String?
    public var posterURL: URL?
    public var isInfamous: Bool
    public var hostRating: Double?

    public init(
        id: String,
        title: String,
        year: Int,
        genre: String,
        categories: [String] = [],
        episodeIds: [String] = [],
        episodeTitle: String? = nil,
        posterURL: URL? = nil,
        isInfamous: Bool = false,
        hostRating: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.year = year
        self.genre = genre
        self.categories = categories
        self.episodeIds = episodeIds
        self.episodeTitle = episodeTitle
        self.posterURL = posterURL
        self.isInfamous = isInfamous
        self.hostRating = hostRating
    }

    enum CodingKeys: String, CodingKey {
        case id, title, year, genre, categories, episodeIds, episodeTitle, posterURL, isInfamous, hostRating
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        year = try c.decode(Int.self, forKey: .year)
        genre = try c.decode(String.self, forKey: .genre)
        categories = try c.decodeIfPresent([String].self, forKey: .categories) ?? []
        episodeIds = try c.decodeIfPresent([String].self, forKey: .episodeIds) ?? []
        episodeTitle = try c.decodeIfPresent(String.self, forKey: .episodeTitle)
        posterURL = try c.decodeIfPresent(URL.self, forKey: .posterURL)
        isInfamous = try c.decodeIfPresent(Bool.self, forKey: .isInfamous) ?? false
        hostRating = try c.decodeIfPresent(Double.self, forKey: .hostRating)
    }
}

/// One slice of the wheel.
public struct RouletteCategory: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    /// Short label drawn on the wheel (keep it legible with many segments).
    public var name: String
    /// Longer name for lists/stats. Falls back to `name` when nil.
    public var fullName: String?
    /// "#RRGGBB" (or "#RRGGBBAA").
    public var colorHex: String
    /// Relative size of the slice. `nil` means 1. Slice size == landing odds.
    public var weight: Double?
    public var movieIds: [String]

    public init(
        id: String,
        name: String,
        fullName: String? = nil,
        colorHex: String,
        weight: Double? = nil,
        movieIds: [String] = []
    ) {
        self.id = id
        self.name = name
        self.fullName = fullName
        self.colorHex = colorHex
        self.weight = weight
        self.movieIds = movieIds
    }

    public var displayName: String { fullName ?? name }

    enum CodingKeys: String, CodingKey {
        case id, name, fullName, colorHex, weight, movieIds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        fullName = try c.decodeIfPresent(String.self, forKey: .fullName)
        colorHex = try c.decode(String.self, forKey: .colorHex)
        weight = try c.decodeIfPresent(Double.self, forKey: .weight)
        movieIds = try c.decodeIfPresent([String].self, forKey: .movieIds) ?? []
    }
}

/// The full data set behind the wheel. Categories are listed in wheel order:
/// index 0 is the slice that starts at 12 o'clock, then clockwise.
public struct MovieCatalog: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var show: ShowInfo?
    public var categories: [RouletteCategory]
    public var movies: [Movie]

    public init(
        schemaVersion: Int = 1,
        show: ShowInfo? = nil,
        categories: [RouletteCategory],
        movies: [Movie]
    ) {
        self.schemaVersion = schemaVersion
        self.show = show
        self.categories = categories
        self.movies = movies
    }

    public var showInfo: ShowInfo { show ?? .mrt }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, show, categories, movies
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        show = try c.decodeIfPresent(ShowInfo.self, forKey: .show)
        categories = try c.decode([RouletteCategory].self, forKey: .categories)
        movies = try c.decode([Movie].self, forKey: .movies)
    }

    public func movie(withId id: String) -> Movie? {
        movies.first { $0.id == id }
    }

    /// Copy with duplicate movie ids and duplicate category ids removed (first
    /// occurrence wins). Duplicates are reported by `validationIssues`; at
    /// runtime they must never break list identity or dictionary building.
    public func deduplicated() -> MovieCatalog {
        var seenMovies = Set<String>()
        var seenCategories = Set<String>()
        var copy = self
        copy.movies = movies.filter { seenMovies.insert($0.id).inserted }
        copy.categories = categories.filter { seenCategories.insert($0.id).inserted }
        return copy
    }

    public func category(withId id: String) -> RouletteCategory? {
        categories.first { $0.id == id }
    }

    public func movie(forEpisodeGuid guid: String) -> Movie? {
        movies.first { $0.episodeIds.contains(guid) }
    }

    /// Human-readable data problems. Empty means the catalog is consistent.
    public func validationIssues() -> [String] {
        var issues: [String] = []
        let movieIds = movies.map(\.id)
        let categoryIds = categories.map(\.id)

        for id in Set(movieIds) where movieIds.filter({ $0 == id }).count > 1 {
            issues.append("Duplicate movie id '\(id)'")
        }
        for id in Set(categoryIds) where categoryIds.filter({ $0 == id }).count > 1 {
            issues.append("Duplicate category id '\(id)'")
        }

        let knownMovies = Set(movieIds)
        let knownCategories = Set(categoryIds)
        for category in categories {
            if HexColor(category.colorHex) == nil {
                issues.append("Category '\(category.id)' has invalid colorHex '\(category.colorHex)'")
            }
            if category.movieIds.isEmpty {
                issues.append("Category '\(category.id)' has no movies")
            }
            for movieId in category.movieIds {
                if !knownMovies.contains(movieId) {
                    issues.append("Category '\(category.id)' references unknown movie '\(movieId)'")
                } else if let movie = movie(withId: movieId), !movie.categories.contains(category.id) {
                    issues.append("Movie '\(movieId)' is listed in '\(category.id)' but doesn't list that category")
                }
            }
        }
        for movie in movies {
            for categoryId in movie.categories {
                if !knownCategories.contains(categoryId) {
                    issues.append("Movie '\(movie.id)' references unknown category '\(categoryId)'")
                } else if let category = category(withId: categoryId), !category.movieIds.contains(movie.id) {
                    issues.append("Movie '\(movie.id)' lists '\(categoryId)' but that category doesn't list it")
                }
            }
        }
        return issues.sorted()
    }
}

/// One spin, logged locally on this device.
public struct SpinResult: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let movieId: String
    public let categoryId: String
    public let timestamp: Date

    public init(id: UUID = UUID(), movieId: String, categoryId: String, timestamp: Date = Date()) {
        self.id = id
        self.movieId = movieId
        self.categoryId = categoryId
        self.timestamp = timestamp
    }
}

/// One podcast episode from the Buzzsprout RSS feed.
public struct PodcastEpisode: Codable, Hashable, Identifiable, Sendable {
    public var id: String { guid }
    public let guid: String
    public var title: String
    public var pubDate: Date?
    public var link: URL?
    public var season: Int?
    public var episode: Int?
    public var episodeType: String?
    public var summary: String
    /// Per-episode artwork (`<itunes:image href>` on the item). Optional so
    /// feed caches written before artwork support still decode (as nil).
    public var imageURL: URL?

    public init(
        guid: String,
        title: String,
        pubDate: Date? = nil,
        link: URL? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        episodeType: String? = nil,
        summary: String = "",
        imageURL: URL? = nil
    ) {
        self.guid = guid
        self.title = title
        self.pubDate = pubDate
        self.link = link
        self.season = season
        self.episode = episode
        self.episodeType = episodeType
        self.summary = summary
        self.imageURL = imageURL
    }

    /// "S4E34" when season/episode are known.
    public var seasonEpisodeLabel: String? {
        guard let season, let episode else { return nil }
        return "S\(season)E\(episode)"
    }
}
