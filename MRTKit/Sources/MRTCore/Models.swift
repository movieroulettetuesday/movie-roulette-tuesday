import Foundation

/// App-wide feature switches.
public enum FeatureFlags {
    /// Host Rating UI (movie page "Host Rating" section, Stats "You vs hosts").
    /// Hidden for now; the `Movie.hostRating` field, its decoding and the
    /// `PersonalRatings.versusHosts` logic stay in place. To re-enable: set this
    /// to `true` and add `"hostRating"` values to movies.json.
    public static let showHostRatings = false
}

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
    /// TMDB movie id (future "Where to stream"; no UI yet). Optional, so
    /// catalogs without it still decode.
    public var tmdbId: Int?
    /// Streaming providers, precomputed into movies.json (future feature;
    /// no UI yet). Optional and tolerant.
    public var streaming: StreamingInfo?

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
        hostRating: Double? = nil,
        tmdbId: Int? = nil,
        streaming: StreamingInfo? = nil
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
        self.tmdbId = tmdbId
        self.streaming = streaming
    }

    enum CodingKeys: String, CodingKey {
        case id, title, year, genre, categories, episodeIds, episodeTitle, posterURL, isInfamous, hostRating
        case tmdbId, streaming
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
        // New optional fields never fail the catalog: a malformed value reads as nil.
        tmdbId = (try? c.decodeIfPresent(Int.self, forKey: .tmdbId)) ?? nil
        streaming = (try? c.decodeIfPresent(StreamingInfo.self, forKey: .streaming)) ?? nil
    }
}

/// Where a movie streams (TMDB watch/providers, data by JustWatch),
/// precomputed into movies.json. Data model only; no UI yet.
/// JSON: {"region":"US","updated":"YYYY-MM-DD","link":"…","stream":[…],"free":[…],"rent":[…],"buy":[…]}
public struct StreamingInfo: Codable, Hashable, Sendable {
    /// {"id":8,"name":"Netflix","logo":"/abc.jpg","priority":1}
    public struct Provider: Codable, Hashable, Sendable {
        public static let logoBase = "https://image.tmdb.org/t/p/w92"
        public var id: Int
        public var name: String
        /// TMDB `logo_path`.
        public var logo: String?
        public var priority: Int?

        public init(id: Int, name: String, logo: String? = nil, priority: Int? = nil) {
            self.id = id
            self.name = name
            self.logo = logo
            self.priority = priority
        }

        public var logoURL: URL? {
            guard let logo, !logo.isEmpty else { return nil }
            return URL(string: Self.logoBase + (logo.hasPrefix("/") ? logo : "/" + logo))
        }
    }

    public var region: String
    /// "YYYY-MM-DD"
    public var updated: String?
    /// TMDB "All options" page.
    public var link: String?
    public var stream: [Provider]
    public var free: [Provider]
    public var rent: [Provider]
    public var buy: [Provider]

    public init(region: String = "US", updated: String? = nil, link: String? = nil,
                stream: [Provider] = [], free: [Provider] = [], rent: [Provider] = [], buy: [Provider] = []) {
        self.region = region
        self.updated = updated
        self.link = link
        self.stream = stream
        self.free = free
        self.rent = rent
        self.buy = buy
    }

    enum CodingKeys: String, CodingKey { case region, updated, link, stream, free, rent, buy }

    /// Lists may be missing or empty; a malformed provider list reads as empty.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func list(_ k: CodingKeys) -> [Provider] { ((try? c.decodeIfPresent([Provider].self, forKey: k)) ?? nil) ?? [] }
        region = ((try? c.decodeIfPresent(String.self, forKey: .region)) ?? nil) ?? "US"
        updated = (try? c.decodeIfPresent(String.self, forKey: .updated)) ?? nil
        link = (try? c.decodeIfPresent(String.self, forKey: .link)) ?? nil
        stream = list(.stream)
        free = list(.free)
        rent = list(.rent)
        buy = list(.buy)
    }

    public var isEmpty: Bool { stream.isEmpty && free.isEmpty && rent.isEmpty && buy.isEmpty }
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
    /// Buzzsprout "Send us Fan Mail" link from the show-notes HTML. Optional so
    /// older feed caches still decode (as nil).
    public var fanMailURL: URL?

    public init(
        guid: String,
        title: String,
        pubDate: Date? = nil,
        link: URL? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        episodeType: String? = nil,
        summary: String = "",
        imageURL: URL? = nil,
        fanMailURL: URL? = nil
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
        self.fanMailURL = fanMailURL
    }

    /// Show notes without Buzzsprout's leading "Send us Fan Mail" line. Applied at
    /// display time too, so summaries cached by older builds are cleaned.
    public var displaySummary: String { ShowNotes.strippingFanMail(summary) }

    /// "S4E34" when season/episode are known.
    public var seasonEpisodeLabel: String? {
        guard let season, let episode else { return nil }
        return "S\(season)E\(episode)"
    }
}

/// Buzzsprout injects a "Send us Fan Mail" link at the start of every episode's
/// show notes; as plain text it is noise, so it is stripped and offered as a link.
public enum ShowNotes {
    /// Removes a leading "Send us fan mail" phrase (any case, optional trailing
    /// punctuation) from plain-text show notes.
    public static func strippingFanMail(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^send us fan ?mail[\s.:!\-–—|]*"#
        guard let range = trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
            return trimmed
        }
        return String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The href of the "Send us Fan Mail" anchor (or any Buzzsprout fan_mail
    /// link) in show-notes HTML; nil when absent or not http(s).
    public static func fanMailURL(inHTML html: String) -> URL? {
        let anchor = #"<a\b[^>]*href\s*=\s*["']([^"']+)["'][^>]*>\s*([^<]*)</a>"#
        guard let re = try? NSRegularExpression(pattern: anchor, options: [.caseInsensitive]) else { return nil }
        let ns = html as NSString
        for m in re.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let href = ns.substring(with: m.range(at: 1)).replacingOccurrences(of: "&amp;", with: "&")
            let label = ns.substring(with: m.range(at: 2))
            let isFanMail = href.lowercased().contains("fan_mail")
                || label.range(of: #"fan ?mail"#, options: [.regularExpression, .caseInsensitive]) != nil
            guard isFanMail, let url = URL(string: href),
                  let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { continue }
            return url
        }
        return nil
    }
}

/// Totals shown under the Episodes and Movies lists. The feed also carries
/// trailers, bonus and non-movie episodes, so "episodes in the feed" and
/// "films in the catalog" differ; both footers label which count they show.
public struct EpisodeTotals: Equatable, Sendable {
    /// Every episode in the Buzzsprout feed.
    public let feedEpisodes: Int
    /// Feed episodes that discuss a film in the catalog (Movies tab).
    public let feedEpisodesWithFilm: Int

    public init(episodes: [PodcastEpisode], catalog: MovieCatalog?) {
        feedEpisodes = episodes.count
        feedEpisodesWithFilm = catalog.map { c in episodes.filter { c.movie(forEpisodeGuid: $0.guid) != nil }.count } ?? 0
    }

    /// Distinct episodes linked from the catalog's films.
    public static func catalogEpisodeCount(_ catalog: MovieCatalog?) -> Int {
        Set(catalog?.movies.flatMap(\.episodeIds) ?? []).count
    }
}

extension MovieCatalog {
    /// The line under a movie's title: year plus the same category names the
    /// movie page's "Categories" section lists (catalog categories, not `genre`).
    public func subtitle(for movie: Movie) -> String {
        let names = movie.categories.compactMap { category(withId: $0)?.displayName }
        return names.isEmpty ? "\(movie.year) · \(movie.genre)" : "\(movie.year) · " + names.joined(separator: ", ")
    }
}

// MARK: - Where to stream (feature 6): pure logic

/// The user's streaming services (provider ids), saved locally as "8,9,337".
public struct MyServices: Equatable, Sendable {
    public static let storageKey = "streaming.myServices"
    public private(set) var ids: Set<Int>

    public init(ids: Set<Int> = []) { self.ids = ids }

    public init(serialized: String) {
        ids = Set(serialized.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) })
    }

    public var serialized: String { ids.sorted().map(String.init).joined(separator: ",") }
    public var isEmpty: Bool { ids.isEmpty }
    public func contains(_ id: Int) -> Bool { ids.contains(id) }

    public mutating func toggle(_ id: Int) {
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
    }
}

/// What the movie page's "Where to Watch" section shows. The section is always
/// present; without providers it shows `emptyMessage`. The TMDB link and the
/// JustWatch/TMDB footer appear only when the movie has a tmdbId or a link.
public struct WhereToWatchDisplay: Equatable, Sendable {
    public static let emptyMessage = "No streaming sources found."
    public var region: String
    public var showsProviders: Bool
    public var link: URL?
    /// Attribution (+ " · updated <date>" when known); nil = message only.
    public var footer: String?

    public var showsEmptyMessage: Bool { !showsProviders }

    public init(movie: Movie) {
        let s = movie.streaming
        region = s?.region ?? "US"
        showsProviders = !(s?.isEmpty ?? true)
        if let l = s?.link.flatMap(URL.init(string:)) {
            link = l
        } else if let id = movie.tmdbId {
            link = URL(string: "https://www.themoviedb.org/movie/\(id)/watch?locale=\(region)")
        } else {
            link = nil
        }
        if link != nil || showsProviders {
            if let date = StreamingCatalog.updatedLabel(s?.updated) {
                footer = "\(StreamingCatalog.attribution) · updated \(date)"
            } else {
                footer = StreamingCatalog.attribution
            }
        } else {
            footer = nil
        }
    }
}

public enum StreamingCatalog {
    /// Attribution required by TMDB/JustWatch, shown next to the data.
    public static let attribution = "Streaming data by JustWatch via TMDB"
    public static let tmdbNotice = "This product uses the TMDB API but is not endorsed or certified by TMDB."

    /// Subscription/free services found in the catalog (stream + free lists),
    /// for Settings › My Services: most titles first, then by name.
    public static func services(in movies: [Movie]) -> [StreamingInfo.Provider] {
        var byId: [Int: StreamingInfo.Provider] = [:]
        var counts: [Int: Int] = [:]
        for m in movies {
            guard let s = m.streaming else { continue }
            var seen = Set<Int>()
            for p in s.stream + s.free where seen.insert(p.id).inserted {
                if byId[p.id] == nil || (byId[p.id]?.logo == nil && p.logo != nil) { byId[p.id] = p }
                counts[p.id, default: 0] += 1
            }
        }
        return byId.values.sorted {
            let a = counts[$0.id] ?? 0, b = counts[$1.id] ?? 0
            return a != b ? a > b : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Providers of `movie` (stream, then free) that are among `services`.
    public static func matchingServices(_ movie: Movie, services: MyServices) -> [StreamingInfo.Provider] {
        guard let s = movie.streaming else { return [] }
        var seen = Set<Int>()
        return (s.stream + s.free).filter { services.contains($0.id) && seen.insert($0.id).inserted }
    }

    public static func isOnMyServices(_ movie: Movie, services: MyServices) -> Bool {
        !matchingServices(movie, services: services).isEmpty
    }

    /// Streams or is free anywhere (used when no services are chosen yet).
    public static func isStreamable(_ movie: Movie) -> Bool {
        guard let s = movie.streaming else { return false }
        return !s.stream.isEmpty || !s.free.isEmpty
    }

    /// "On my services" filter. No services chosen -> nothing matches.
    public static func filter(_ movies: [Movie], services: MyServices) -> [Movie] {
        movies.filter { isOnMyServices($0, services: services) }
    }

    /// "Available first": stable partition, keeping the incoming order within
    /// each part. Available = on my services, or (no services chosen) streamable
    /// anywhere; then rent/buy-only; then no data.
    public static func availableFirst(_ movies: [Movie], services: MyServices) -> [Movie] {
        func rank(_ m: Movie) -> Int {
            if services.isEmpty ? isStreamable(m) : isOnMyServices(m, services: services) { return 0 }
            if services.isEmpty == false, isStreamable(m) { return 1 }
            if let s = m.streaming, !s.rent.isEmpty || !s.buy.isEmpty { return 2 }
            return 3
        }
        return movies.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }

    /// Rent and buy merged, de-duplicated (rent order first).
    public static func rentOrBuy(_ info: StreamingInfo) -> [StreamingInfo.Provider] {
        var seen = Set<Int>()
        return (info.rent + info.buy).filter { seen.insert($0.id).inserted }
    }

    /// "Oct 13" from "2026-10-13" (nil when unparseable).
    public static func updatedLabel(_ updated: String?, locale: Locale = Locale(identifier: "en_US")) -> String? {
        guard let updated else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: updated) else { return nil }
        let out = DateFormatter()
        out.locale = locale
        out.timeZone = TimeZone(identifier: "UTC")
        out.setLocalizedDateFormatFromTemplate("MMM d")
        return out.string(from: d)
    }
}
