import Foundation

public enum AppGroup {
    public static let identifier = "group.com.movieroulettetuesday.app"
}

/// Small JSON blob the app writes into the App Group container for the widget.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public struct EpisodeInfo: Codable, Equatable, Sendable {
        public var guid: String
        public var title: String
        public var season: Int?
        public var episode: Int?
        public var pubDate: Date?

        public init(guid: String, title: String, season: Int? = nil, episode: Int? = nil, pubDate: Date? = nil) {
            self.guid = guid
            self.title = title
            self.season = season
            self.episode = episode
            self.pubDate = pubDate
        }

        public init(episode: PodcastEpisode) {
            self.init(guid: episode.guid, title: episode.title, season: episode.season,
                      episode: episode.episode, pubDate: episode.pubDate)
        }

        public var seasonEpisodeLabel: String? {
            guard let season, let episode else { return nil }
            return "S\(season)E\(episode)"
        }
    }

    public struct SpinInfo: Codable, Equatable, Sendable {
        public var movieId: String
        public var title: String
        public var year: Int
        public var categoryName: String
        public var colorHex: String
        public var timestamp: Date

        public init(movieId: String, title: String, year: Int, categoryName: String, colorHex: String, timestamp: Date) {
            self.movieId = movieId
            self.title = title
            self.year = year
            self.categoryName = categoryName
            self.colorHex = colorHex
            self.timestamp = timestamp
        }
    }

    public var latestEpisode: EpisodeInfo?
    public var lastSpin: SpinInfo?
    public var updatedAt: Date

    public init(latestEpisode: EpisodeInfo? = nil, lastSpin: SpinInfo? = nil, updatedAt: Date = Date()) {
        self.latestEpisode = latestEpisode
        self.lastSpin = lastSpin
        self.updatedAt = updatedAt
    }

    /// Newest episode by publish date (feed order as tie-breaker).
    public static func latest(in episodes: [PodcastEpisode]) -> PodcastEpisode? {
        episodes.enumerated().max { a, b in
            let da = a.element.pubDate ?? .distantPast
            let db = b.element.pubDate ?? .distantPast
            return da == db ? a.offset > b.offset : da < db
        }?.element
    }
}

/// Reads/writes `widget-snapshot.json`. `appGroup()` returns nil when the
/// App Group container isn't available (no team / entitlement yet, or Linux),
/// and the widget then falls back to Spin of the Day only.
public struct WidgetSnapshotStore: Sendable {
    public static let fileName = "widget-snapshot.json"
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func appGroup(identifier: String = AppGroup.identifier) -> WidgetSnapshotStore? {
        #if canImport(Darwin)
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            return nil
        }
        return WidgetSnapshotStore(fileURL: container.appendingPathComponent(fileName))
        #else
        return nil
        #endif
    }

    /// nil when missing or unreadable.
    public func load() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    public func save(_ snapshot: WidgetSnapshot) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
    }

    /// Applies `mutate` and saves. Returns false (and skips the write) when
    /// nothing but `updatedAt` would change, so callers can avoid needless widget reloads.
    @discardableResult
    public func update(now: Date = Date(), _ mutate: (inout WidgetSnapshot) -> Void) throws -> Bool {
        let existing = load()
        var next = existing ?? WidgetSnapshot(updatedAt: now)
        mutate(&next)
        if let existing, existing.latestEpisode == next.latestEpisode, existing.lastSpin == next.lastSpin {
            return false
        }
        next.updatedAt = now
        try save(next)
        return true
    }
}
