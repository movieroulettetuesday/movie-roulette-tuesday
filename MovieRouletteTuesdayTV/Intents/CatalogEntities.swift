import AppIntents
#if os(iOS)
import CoreSpotlight
#endif
import Foundation
import UniformTypeIdentifiers
import MRTCore
import MRTShared

/// A catalog movie Siri, Shortcuts, and Spotlight can name.
///
/// Only public catalog fields are stored. Ratings and watchlist status are
/// never properties of this type, so they cannot be indexed or spoken from it.
struct MovieEntity: AppEntity, Identifiable, Equatable, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Movie")
    static let defaultQuery = MovieEntityQuery()
    /// Placeholder so an intent can be constructed before Siri fills the parameter.
    static let placeholder = MovieEntity(id: "", title: "", year: 0, genre: "", categoryNames: [], episodeLabel: nil)

    var id: String
    var title: String
    var year: Int
    var genre: String
    var categoryNames: [String]
    /// Public episode label ("S4E39" or the episode title). Nil when it would
    /// only repeat the movie title.
    var episodeLabel: String?

    init(movie: Movie, catalog: MovieCatalog, episodesByGUID: [String: PodcastEpisode] = [:]) {
        id = movie.id
        title = movie.title
        year = movie.year
        genre = movie.genre
        categoryNames = movie.categories.compactMap { catalog.category(withId: $0)?.displayName }
        episodeLabel = Self.episodeLabel(for: movie, episodesByGUID: episodesByGUID)
    }

    init(id: String, title: String, year: Int, genre: String, categoryNames: [String], episodeLabel: String?) {
        self.id = id
        self.title = title
        self.year = year
        self.genre = genre
        self.categoryNames = categoryNames
        self.episodeLabel = episodeLabel
    }

    var subtitle: String {
        var parts = [String(year), genre]
        if let episodeLabel, !episodeLabel.isEmpty { parts.append(episodeLabel) }
        return parts.joined(separator: " · ")
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(subtitle)")
    }

    /// The only strings Spotlight is allowed to store for this movie.
    var spotlightRecord: PublicIndexRecord {
        var keywords = [genre, String(year)] + categoryNames
        if let episodeLabel, !episodeLabel.isEmpty { keywords.append(episodeLabel) }
        var seen = Set<String>()
        keywords = keywords.filter { seen.insert($0).inserted }
        return PublicIndexRecord(id: id, title: title, subtitle: subtitle, keywords: keywords)
    }

    private static func episodeLabel(for movie: Movie, episodesByGUID: [String: PodcastEpisode]) -> String? {
        if let guid = movie.episodeIds.first, let label = episodesByGUID[guid]?.seasonEpisodeLabel, !label.isEmpty {
            return label
        }
        guard let title = movie.episodeTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return nil
        }
        let same = title.compare(movie.title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        return same ? nil : title
    }
}

/// A podcast episode from the public RSS cache. No personal data.
struct EpisodeEntity: AppEntity, Identifiable, Equatable, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Episode")
    static let defaultQuery = EpisodeEntityQuery()

    var id: String
    var title: String
    var seasonEpisodeLabel: String?
    var dateDescription: String

    init(episode: PodcastEpisode) {
        id = episode.guid
        title = episode.title
        seasonEpisodeLabel = episode.seasonEpisodeLabel
        if let date = episode.pubDate {
            dateDescription = date.formatted(date: .abbreviated, time: .omitted)
        } else {
            dateDescription = ""
        }
    }

    var subtitle: String {
        [seasonEpisodeLabel, dateDescription.isEmpty ? nil : dateDescription]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var displayRepresentation: DisplayRepresentation {
        if subtitle.isEmpty {
            return DisplayRepresentation(title: "\(title)")
        }
        return DisplayRepresentation(title: "\(title)", subtitle: "\(subtitle)")
    }

    var spotlightRecord: PublicIndexRecord {
        var keywords: [String] = []
        if let seasonEpisodeLabel { keywords.append(seasonEpisodeLabel) }
        if !dateDescription.isEmpty { keywords.append(dateDescription) }
        return PublicIndexRecord(id: id, title: title, subtitle: subtitle, keywords: keywords)
    }
}

/// Strings written to Spotlight. There is no rating or watchlist field.
struct PublicIndexRecord: Equatable, Sendable {
    var id: String
    var title: String
    var subtitle: String
    var keywords: [String]

    var indexedText: String {
        ([title, subtitle] + keywords).joined(separator: "\n")
    }
}

enum SpotlightDonation {
    static func movieEntities(catalog: MovieCatalog, episodes: [PodcastEpisode]) -> [MovieEntity] {
        let episodesByGUID = EpisodeCacheReader.byGUID(episodes)
        return catalog.movies.map { MovieEntity(movie: $0, catalog: catalog, episodesByGUID: episodesByGUID) }
    }

    static func episodeEntities(_ episodes: [PodcastEpisode]) -> [EpisodeEntity] {
        episodes.map(EpisodeEntity.init(episode:))
    }

    static func movieRecords(catalog: MovieCatalog, episodes: [PodcastEpisode]) -> [PublicIndexRecord] {
        movieEntities(catalog: catalog, episodes: episodes).map(\.spotlightRecord)
    }

    static func episodeRecords(_ episodes: [PodcastEpisode]) -> [PublicIndexRecord] {
        episodeEntities(episodes).map(\.spotlightRecord)
    }
}

#if os(iOS)
@available(iOS 18.0, *)
extension MovieEntity: IndexedEntity {
    var attributeSet: CSSearchableItemAttributeSet {
        publicAttributeSet(from: spotlightRecord)
    }
}

@available(iOS 18.0, *)
extension EpisodeEntity: IndexedEntity {
    var attributeSet: CSSearchableItemAttributeSet {
        publicAttributeSet(from: spotlightRecord)
    }
}

@available(iOS 18.0, *)
private func publicAttributeSet(from record: PublicIndexRecord) -> CSSearchableItemAttributeSet {
    let set = CSSearchableItemAttributeSet(contentType: .content)
    set.title = record.title
    set.contentDescription = record.subtitle
    set.keywords = record.keywords
    return set
}
#endif

// MARK: - Queries

struct MovieEntityQuery: EntityQuery, EntityStringQuery {
    func entities(for identifiers: [MovieEntity.ID]) async throws -> [MovieEntity] {
        let catalog = try await IntentCatalog.load()
        let episodes = await MainActor.run { EpisodeCacheReader.byGUID(IntentRuntime.episodes()) }
        return MovieEntityLookup.entities(for: identifiers, in: catalog, episodesByGUID: episodes)
    }

    func suggestedEntities() async throws -> [MovieEntity] {
        let catalog = try await IntentCatalog.load()
        let episodes = await MainActor.run { EpisodeCacheReader.byGUID(IntentRuntime.episodes()) }
        return MovieEntityLookup.suggested(in: catalog, episodesByGUID: episodes, limit: 8)
    }

    func entities(matching string: String) async throws -> [MovieEntity] {
        let catalog = try await IntentCatalog.load()
        let episodes = await MainActor.run { EpisodeCacheReader.byGUID(IntentRuntime.episodes()) }
        return MovieEntityLookup.matching(string, in: catalog, episodesByGUID: episodes)
    }
}

struct EpisodeEntityQuery: EntityQuery, EntityStringQuery {
    func entities(for identifiers: [EpisodeEntity.ID]) async throws -> [EpisodeEntity] {
        let episodes = await MainActor.run { IntentRuntime.episodes() }
        return EpisodeEntityLookup.entities(for: identifiers, in: episodes)
    }

    func suggestedEntities() async throws -> [EpisodeEntity] {
        let episodes = await MainActor.run { IntentRuntime.episodes() }
        return EpisodeEntityLookup.suggested(in: episodes, limit: 8)
    }

    func entities(matching string: String) async throws -> [EpisodeEntity] {
        let episodes = await MainActor.run { IntentRuntime.episodes() }
        return EpisodeEntityLookup.matching(string, in: episodes)
    }
}

enum MovieEntityLookup {
    static func entity(id: String, in catalog: MovieCatalog, episodesByGUID: [String: PodcastEpisode] = [:]) -> MovieEntity? {
        catalog.movie(withId: id).map { MovieEntity(movie: $0, catalog: catalog, episodesByGUID: episodesByGUID) }
    }

    static func entities(for ids: [String], in catalog: MovieCatalog, episodesByGUID: [String: PodcastEpisode] = [:]) -> [MovieEntity] {
        ids.compactMap { entity(id: $0, in: catalog, episodesByGUID: episodesByGUID) }
    }

    /// A short public list for the Shortcuts picker. Not the watchlist.
    static func suggested(in catalog: MovieCatalog, episodesByGUID: [String: PodcastEpisode] = [:], limit: Int) -> [MovieEntity] {
        catalog.movies
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .prefix(max(0, limit))
            .map { MovieEntity(movie: $0, catalog: catalog, episodesByGUID: episodesByGUID) }
    }

    /// Title, year, genre, or category. An unknown string is an empty list.
    /// A year in the query ("The Thing 1982") is a disambiguator.
    static func matching(_ raw: String, in catalog: MovieCatalog, episodesByGUID: [String: PodcastEpisode] = [:]) -> [MovieEntity] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        let year = tokens.compactMap(Int.init).first { (1880...2100).contains($0) }
        let needle = fold(tokens.filter { token in
            guard let value = Int(token) else { return true }
            return !(1880...2100).contains(value)
        }.joined(separator: " "))

        let hits = catalog.movies.filter { movie in
            let yearOK = year == nil || movie.year == year
            guard yearOK else { return false }
            guard !needle.isEmpty else { return true }
            let title = fold(movie.title)
            if title.contains(needle) { return true }
            if fold(movie.genre).contains(needle) { return true }
            let categories = movie.categories.compactMap { catalog.category(withId: $0)?.displayName }
            return categories.contains { fold($0).contains(needle) }
        }
        return hits.sorted { lhs, rhs in
            let left = rank(lhs, needle: needle)
            let right = rank(rhs, needle: needle)
            if left.0 != right.0 { return left.0 < right.0 }
            return left.1.localizedCaseInsensitiveCompare(right.1) == .orderedAscending
        }.map { MovieEntity(movie: $0, catalog: catalog, episodesByGUID: episodesByGUID) }
    }

    private static func rank(_ movie: Movie, needle: String) -> (Int, String) {
        let title = fold(movie.title)
        let score: Int
        if needle.isEmpty || title == needle { score = 0 }
        else if title.hasPrefix(needle) { score = 1 }
        else { score = 2 }
        return (score, movie.title)
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
            .replacingOccurrences(of: "‘", with: "")
    }
}

enum EpisodeEntityLookup {
    static func entities(for ids: [String], in episodes: [PodcastEpisode]) -> [EpisodeEntity] {
        let byID = Dictionary(episodes.map { ($0.guid, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0].map(EpisodeEntity.init(episode:)) }
    }

    static func suggested(in episodes: [PodcastEpisode], limit: Int) -> [EpisodeEntity] {
        let newest = episodes.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
        return newest.prefix(max(0, limit)).map(EpisodeEntity.init(episode:))
    }

    static func matching(_ raw: String, in episodes: [PodcastEpisode]) -> [EpisodeEntity] {
        let needle = MovieEntityLookup.fold(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return [] }
        return episodes.filter { MovieEntityLookup.fold($0.title).contains(needle) }
            .map(EpisodeEntity.init(episode:))
    }
}

enum EpisodeCacheReader {
    static func cachedEpisodes() -> [PodcastEpisode] {
        guard let url = try? EpisodeFeedIO.cacheURL() else { return [] }
        return (try? EpisodeFeedIO.loadCache(from: url))?.episodes ?? []
    }

    static func byGUID(_ episodes: [PodcastEpisode]) -> [String: PodcastEpisode] {
        Dictionary(episodes.map { ($0.guid, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

/// Services Siri can say in "Open [movie] on Netflix". The URL still comes
/// from `ProviderLaunching`; these ids are the same ones that type already maps.
enum StreamingProviderOption: String, AppEnum, Sendable {
    case netflix
    case prime
    case max
    case appleTV
    case disney
    case hulu
    case paramount
    case peacock
    case tubi
    case criterion
    case youtube
    case mubi
    case pluto
    case shudder
    case tcm

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Streaming Service")
    }

    static var caseDisplayRepresentations: [StreamingProviderOption: DisplayRepresentation] {
        [
            .netflix: "Netflix",
            .prime: "Prime Video",
            .max: "Max",
            .appleTV: "Apple TV",
            .disney: "Disney+",
            .hulu: "Hulu",
            .paramount: "Paramount+",
            .peacock: "Peacock",
            .tubi: "Tubi",
            .criterion: "Criterion Channel",
            .youtube: "YouTube",
            .mubi: "MUBI",
            .pluto: "Pluto TV",
            .shudder: "Shudder",
            .tcm: "TCM",
        ]
    }

    var syntheticProvider: StreamingInfo.Provider {
        switch self {
        case .netflix: return StreamingInfo.Provider(id: 8, name: "Netflix")
        case .prime: return StreamingInfo.Provider(id: 9, name: "Prime Video")
        case .max: return StreamingInfo.Provider(id: 1899, name: "Max")
        case .appleTV: return StreamingInfo.Provider(id: 2, name: "Apple TV")
        case .disney: return StreamingInfo.Provider(id: 337, name: "Disney+")
        case .hulu: return StreamingInfo.Provider(id: 15, name: "Hulu")
        case .paramount: return StreamingInfo.Provider(id: 531, name: "Paramount+")
        case .peacock: return StreamingInfo.Provider(id: 386, name: "Peacock")
        case .tubi: return StreamingInfo.Provider(id: 73, name: "Tubi")
        case .criterion: return StreamingInfo.Provider(id: 258, name: "Criterion Channel")
        case .youtube: return StreamingInfo.Provider(id: 192, name: "YouTube")
        case .mubi: return StreamingInfo.Provider(id: 11, name: "MUBI")
        case .pluto: return StreamingInfo.Provider(id: 300, name: "Pluto TV")
        case .shudder: return StreamingInfo.Provider(id: 99, name: "Shudder")
        case .tcm: return StreamingInfo.Provider(id: 361, name: "TCM")
        }
    }

    func matches(_ provider: StreamingInfo.Provider) -> Bool {
        let name = provider.name.lowercased()
        switch self {
        case .netflix: return provider.id == 8 || name.contains("netflix")
        case .prime:
            return provider.id == 9 || provider.id == 10 || name.contains("prime") || name.contains("amazon video")
        case .max: return provider.id == 1899 || provider.id == 384 || name == "max" || name.contains("hbo")
        case .appleTV: return provider.id == 2 || provider.id == 350 || name.hasPrefix("apple")
        case .disney: return provider.id == 337 || name.contains("disney")
        case .hulu: return provider.id == 15 || name.contains("hulu")
        case .paramount: return provider.id == 531 || name.contains("paramount")
        case .peacock: return provider.id == 386 || provider.id == 387 || name.contains("peacock")
        case .tubi: return provider.id == 73 || name.contains("tubi")
        case .criterion: return provider.id == 258 || name.contains("criterion")
        case .youtube: return provider.id == 192 || (name.contains("youtube") && !name.contains("youtube tv"))
        case .mubi: return provider.id == 11 || name.contains("mubi")
        case .pluto: return provider.id == 300 || name.contains("pluto")
        case .shudder: return provider.id == 99 || name.contains("shudder")
        case .tcm: return provider.id == 361 || name.contains("tcm")
        }
    }
}
