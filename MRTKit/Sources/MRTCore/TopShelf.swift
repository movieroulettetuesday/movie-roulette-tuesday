import Foundation

/// Apple TV Top Shelf: the latest episode, shared by the TV app and the
/// Top Shelf extension through the App Group.
///
/// A static 1920×720 image cannot change when a new episode is published, so
/// the extension publishes dynamic content. The asset-catalog image is only
/// the fallback for the moment before any snapshot exists.
///
/// Tapping an item opens `mrt://episode/<guid>`. `TVRootView.open` already
/// routes that URL to the episode page.
public enum TopShelf {
    public static let snapshotFileName = "topshelf-snapshot.json"
    public static let banner1xFileName = "topshelf-banner-1x.png"
    public static let banner2xFileName = "topshelf-banner-2x.png"
    public static let bannerGUIDFileName = "topshelf-banner.guid"
    /// Present when the banner was drawn without episode art that should be retried.
    public static let pendingArtworkFileName = "topshelf-banner.pending-art"

    /// Approved mock size (standard Top Shelf / inset banner).
    public static let insetSize1x = TopShelfPixelSize(width: 1920, height: 720)
    /// @2x inset banner.
    public static let insetSize2x = TopShelfPixelSize(width: 3840, height: 1440)
    /// Asset-catalog "Top Shelf Image Wide" (Apple TV 4K). Same art, extra side margin.
    public static let staticWideSize = TopShelfPixelSize(width: 2320, height: 720)

    /// How long a snapshot stays fresh before the extension re-reads the RSS feed.
    public static let staleAfter: TimeInterval = 6 * 60 * 60
    /// Same window as the TV "NEW" badge (`TVFormat.recentEpisodeWindow`).
    public static let recentEpisodeWindow: TimeInterval = 21 * 24 * 60 * 60
    /// Pub dates a few hours ahead of the device clock still count as new.
    public static let futureSlack: TimeInterval = 24 * 60 * 60
    /// Extension waits this long for episode art, then draws the banner without it.
    public static let artworkFetchTimeout: TimeInterval = 2.5
}

public struct TopShelfPixelSize: Equatable, Sendable, Codable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct TopShelfRect: Equatable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Int { x + width }
}

/// Sectioned Top Shelf image shape for the episode's source art.
/// `.hdtv` is the wide inset banner, not a source image.
public enum TopShelfImageShape: String, Codable, Equatable, Sendable {
    case square
    case poster
    case hdtv
}

/// One latest episode, ready for the shelf. Display strings that depend on
/// locale are formatted later (`TopShelfCopy`); this stores the facts.
public struct TopShelfEpisode: Codable, Equatable, Sendable {
    public var guid: String
    public var title: String
    public var season: Int?
    public var episode: Int?
    public var pubDate: Date?
    public var duration: TimeInterval?
    /// "Listener pick from Kevin" when the show notes name the picker. Nil
    /// when they don't — the shelf never invents a name.
    public var listenerCredit: String?
    public var isNew: Bool
    public var imageURL: URL?
    public var imageShape: TopShelfImageShape
    /// Short show name, e.g. "Movie Roulette Tuesday".
    public var showName: String

    public init(
        guid: String,
        title: String,
        season: Int? = nil,
        episode: Int? = nil,
        pubDate: Date? = nil,
        duration: TimeInterval? = nil,
        listenerCredit: String? = nil,
        isNew: Bool = false,
        imageURL: URL? = nil,
        imageShape: TopShelfImageShape = .square,
        showName: String
    ) {
        self.guid = guid
        self.title = title
        self.season = season
        self.episode = episode
        self.pubDate = pubDate
        self.duration = duration
        self.listenerCredit = listenerCredit
        self.isNew = isNew
        self.imageURL = imageURL
        self.imageShape = imageShape
        self.showName = showName
    }

    /// `mrt://episode/<guid>`, the URL Top Shelf selects.
    public var deepLink: URL { DeepLink.episode(guid: guid).url }

    public var seasonEpisodeLabel: String? {
        guard let season, let episode else { return nil }
        return "S\(season)E\(episode)"
    }

    /// Section label for the sectioned fallback: "NEW EPISODE · S4E37".
    public var sectionTitle: String {
        let head = isNew ? "NEW EPISODE" : "Latest Episode"
        if let seasonEpisodeLabel { return "\(head) · \(seasonEpisodeLabel)" }
        return head
    }
}

public struct TopShelfSnapshot: Codable, Equatable, Sendable {
    public var episode: TopShelfEpisode
    public var updatedAt: Date

    public init(episode: TopShelfEpisode, updatedAt: Date = Date()) {
        self.episode = episode
        self.updatedAt = updatedAt
    }
}

public enum TopShelfLoadPlan: Equatable, Sendable {
    /// Snapshot is new enough to publish as-is.
    case useCache
    /// Missing or older than `TopShelf.staleAfter`: re-read the public RSS feed.
    case refresh

    public static func decide(snapshot: TopShelfSnapshot?, now: Date) -> TopShelfLoadPlan {
        guard let snapshot else { return .refresh }
        return TopShelfFreshness.isStale(snapshot.updatedAt, now: now) ? .refresh : .useCache
    }
}

public enum TopShelfFreshness {
    public static func isStale(_ updatedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(updatedAt) >= TopShelf.staleAfter
    }
}

/// What the extension should hand to TVServices. Pure so it can be tested
/// without the tvOS SDK. A banner file whose guid matches the episode uses
/// the inset style (the wide latest-episode banner). Otherwise one sectioned
/// item uses the episode's remote artwork.
public struct TopShelfItemModel: Equatable, Sendable {
    public enum Style: Equatable, Sendable {
        case inset
        case sectioned
    }

    public var guid: String
    public var title: String
    public var sectionTitle: String
    public var deepLink: URL
    public var style: Style
    public var imageShape: TopShelfImageShape
    public var imageURL: URL?
    public var imageURL2x: URL?

    public init(
        guid: String,
        title: String,
        sectionTitle: String,
        deepLink: URL,
        style: Style,
        imageShape: TopShelfImageShape,
        imageURL: URL? = nil,
        imageURL2x: URL? = nil
    ) {
        self.guid = guid
        self.title = title
        self.sectionTitle = sectionTitle
        self.deepLink = deepLink
        self.style = style
        self.imageShape = imageShape
        self.imageURL = imageURL
        self.imageURL2x = imageURL2x
    }
}

public enum TopShelfContentPlan {
    public static func make(episode: TopShelfEpisode, banner1x: URL?, banner2x: URL?) -> TopShelfItemModel {
        if let banner1x {
            return TopShelfItemModel(
                guid: episode.guid,
                title: episode.title,
                sectionTitle: episode.sectionTitle,
                deepLink: episode.deepLink,
                style: .inset,
                imageShape: .hdtv,
                imageURL: banner1x,
                imageURL2x: banner2x ?? banner1x
            )
        }
        return TopShelfItemModel(
            guid: episode.guid,
            title: episode.title,
            sectionTitle: episode.sectionTitle,
            deepLink: episode.deepLink,
            style: .sectioned,
            imageShape: episode.imageShape == .hdtv ? .square : episode.imageShape,
            imageURL: episode.imageURL,
            imageURL2x: episode.imageURL
        )
    }
}

public enum TopShelfCopy {
    public static let newEpisodeBadge = "NEW EPISODE"

    /// "1 hr 23 min", matching `TVFormat.runtime` (the TV app calls this).
    public static func runtime(_ seconds: TimeInterval?) -> String? {
        guard let seconds, seconds > 0, seconds.isFinite else { return nil }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return minutes == 0 ? "\(hours) hr" : "\(hours) hr \(minutes) min" }
        return "\(max(minutes, 1)) min"
    }

    /// "Oct 27, 2026" in en_US. Template follows the locale's order.
    public static func mediumDate(_ date: Date, locale: Locale, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        return formatter.string(from: date)
    }

    /// "S4E37 · Oct 27, 2026".
    public static func metaLine(
        season: Int?,
        episode: Int?,
        pubDate: Date?,
        locale: Locale,
        timeZone: TimeZone
    ) -> String {
        var parts: [String] = []
        if let season, let episode { parts.append("S\(season)E\(episode)") }
        if let pubDate { parts.append(mediumDate(pubDate, locale: locale, timeZone: timeZone)) }
        return parts.joined(separator: " · ")
    }

    /// "Listener pick from Kevin · 1 hr 23 min" when both exist.
    public static func detailLine(listenerCredit: String?, duration: TimeInterval?) -> String? {
        switch (listenerCredit, runtime(duration)) {
        case let (credit?, time?): return "\(credit) · \(time)"
        case let (credit?, nil): return credit
        case let (nil, time?): return time
        default: return nil
        }
    }

    /// "Kevin" from "listener pick from Kevin" or "Kevin's listener pick".
    /// "her listener pick" has no name, so it returns nil.
    public static func listenerCredit(in summary: String) -> String? {
        let text = summary
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
        let patterns = [
            #"listener pick from ([A-Z][A-Za-z'’-]{1,40})"#,
            #"\b([A-Z][A-Za-z'’-]{1,40})'s listener pick\b"#,
        ]
        let ns = text as NSString
        for pattern in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            guard let match = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
                  match.numberOfRanges > 1 else { continue }
            let name = ns.substring(with: match.range(at: 1))
            guard let first = name.first, first.isUppercase else { continue }
            if ["her", "his", "their", "our"].contains(name.lowercased()) { continue }
            return "Listener pick from \(name)"
        }
        return nil
    }

    /// Drops a trailing ": The Podcast" so the shelf matches the show wordmark.
    public static func shelfShowName(from fullName: String) -> String {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = ": The Podcast"
        if trimmed.lowercased().hasSuffix(suffix.lowercased()) {
            let end = trimmed.index(trimmed.endIndex, offsetBy: -suffix.count)
            let short = String(trimmed[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !short.isEmpty { return short }
        }
        return trimmed.isEmpty ? "Movie Roulette Tuesday" : trimmed
    }
}

/// Newest episode by publish date (the same rule as the widget), titled with
/// the catalog film when that guid is linked.
public enum TopShelfEpisodeBuilder {
    public static func make(
        episodes: [PodcastEpisode],
        catalog: MovieCatalog? = nil,
        showArtwork: URL? = nil,
        showName: String? = nil,
        now: Date = Date()
    ) -> TopShelfEpisode? {
        let usable = episodes.filter { !$0.guid.isEmpty && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let latest = WidgetSnapshot.latest(in: usable) else { return nil }
        let movie = catalog?.movie(forEpisodeGuid: latest.guid)
        let filmTitle = movie?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = filmTitle.isEmpty ? latest.title : filmTitle
        let poster = ArtworkResolver.usableURL(movie?.posterURL)
        let episodeArt = ArtworkResolver.usableURL(latest.imageURL)
        let showArt = ArtworkResolver.usableURL(showArtwork)
        let imageURL: URL?
        let imageShape: TopShelfImageShape
        if let poster {
            imageURL = poster
            imageShape = .poster
        } else if let episodeArt {
            imageURL = episodeArt
            imageShape = .square
        } else {
            imageURL = showArt
            imageShape = .square
        }
        let fullName = showName ?? catalog?.showInfo.name ?? ShowInfo.mrt.name
        return TopShelfEpisode(
            guid: latest.guid,
            title: title,
            season: latest.season,
            episode: latest.episode,
            pubDate: latest.pubDate,
            duration: latest.duration,
            listenerCredit: TopShelfCopy.listenerCredit(in: latest.summary),
            isNew: isNew(latest.pubDate, now: now),
            imageURL: imageURL,
            imageShape: imageShape,
            showName: TopShelfCopy.shelfShowName(from: fullName)
        )
    }

    public static func isNew(_ pubDate: Date?, now: Date) -> Bool {
        guard let pubDate else { return false }
        let age = now.timeIntervalSince(pubDate)
        return age < TopShelf.recentEpisodeWindow && age > -TopShelf.futureSlack
    }
}

/// Layout of the approved latest-episode banner (mock 13), in pixels.
/// The extension draws this; tests lock the strings and the poster/text split.
public struct TopShelfBannerLayout: Equatable, Sendable {
    public var canvas: TopShelfPixelSize
    public var poster: TopShelfRect
    public var textColumnX: Int
    public var textColumnWidth: Int
    public var textTop: Int
    public var showsNewBadge: Bool
    public var badgeText: String
    public var metaLine: String
    public var title: String
    public var detailLine: String?
    public var showName: String
    public var titleFontSize: Int
    public var metaFontSize: Int
    public var badgeFontSize: Int
    public var detailFontSize: Int
    public var showFontSize: Int
    public var cornerRadius: Int

    public init(
        canvas: TopShelfPixelSize,
        poster: TopShelfRect,
        textColumnX: Int,
        textColumnWidth: Int,
        textTop: Int,
        showsNewBadge: Bool,
        badgeText: String,
        metaLine: String,
        title: String,
        detailLine: String?,
        showName: String,
        titleFontSize: Int,
        metaFontSize: Int,
        badgeFontSize: Int,
        detailFontSize: Int,
        showFontSize: Int,
        cornerRadius: Int
    ) {
        self.canvas = canvas
        self.poster = poster
        self.textColumnX = textColumnX
        self.textColumnWidth = textColumnWidth
        self.textTop = textTop
        self.showsNewBadge = showsNewBadge
        self.badgeText = badgeText
        self.metaLine = metaLine
        self.title = title
        self.detailLine = detailLine
        self.showName = showName
        self.titleFontSize = titleFontSize
        self.metaFontSize = metaFontSize
        self.badgeFontSize = badgeFontSize
        self.detailFontSize = detailFontSize
        self.showFontSize = showFontSize
        self.cornerRadius = cornerRadius
    }
}

public enum TopShelfBannerMetrics {
    public static func layout(
        for episode: TopShelfEpisode,
        canvas: TopShelfPixelSize,
        locale: Locale = Locale(identifier: "en_US"),
        timeZone: TimeZone = .current
    ) -> TopShelfBannerLayout {
        let height = max(canvas.height, 1)
        let width = max(canvas.width, 1)
        let posterHeight = height * 78 / 100
        let posterWidth = posterHeight * 2 / 3
        let posterX = width * 55 / 1000
        let posterY = (height - posterHeight) / 2
        let gap = width * 40 / 1000
        let textX = posterX + posterWidth + gap
        let margin = width * 55 / 1000
        let textWidth = max(1, width - textX - margin)
        let scale = height
        return TopShelfBannerLayout(
            canvas: TopShelfPixelSize(width: width, height: height),
            poster: TopShelfRect(x: posterX, y: posterY, width: posterWidth, height: posterHeight),
            textColumnX: textX,
            textColumnWidth: textWidth,
            textTop: height * 18 / 100,
            showsNewBadge: episode.isNew,
            badgeText: TopShelfCopy.newEpisodeBadge,
            metaLine: TopShelfCopy.metaLine(
                season: episode.season,
                episode: episode.episode,
                pubDate: episode.pubDate,
                locale: locale,
                timeZone: timeZone
            ),
            title: episode.title,
            detailLine: TopShelfCopy.detailLine(listenerCredit: episode.listenerCredit, duration: episode.duration),
            showName: episode.showName,
            titleFontSize: max(24, scale * 92 / 720),
            metaFontSize: max(16, scale * 28 / 720),
            badgeFontSize: max(14, scale * 22 / 720),
            detailFontSize: max(16, scale * 32 / 720),
            showFontSize: max(16, scale * 30 / 720),
            cornerRadius: max(8, scale * 28 / 720)
        )
    }
}

/// `topshelf-snapshot.json` plus the rendered banner PNGs in one directory
/// (the App Group container). `appGroup()` is nil when the container isn't
/// available (no signing team yet, or Linux); the shelf then keeps the
/// static image.
public struct TopShelfSnapshotStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public var fileURL: URL { directory.appendingPathComponent(TopShelf.snapshotFileName) }

    public static func appGroup(identifier: String = AppGroup.identifier) -> TopShelfSnapshotStore? {
        #if canImport(Darwin)
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            return nil
        }
        return TopShelfSnapshotStore(directory: container)
        #else
        return nil
        #endif
    }

    public func load() -> TopShelfSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(TopShelfSnapshot.self, from: data)
    }

    public func save(_ snapshot: TopShelfSnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
    }

    /// False when the episode is unchanged, so callers can skip a Top Shelf reload.
    /// A stale timestamp is still refreshed, so opening the app keeps the
    /// extension from re-downloading a feed it already confirmed.
    @discardableResult
    public func saveIfChanged(_ snapshot: TopShelfSnapshot) throws -> Bool {
        if let existing = load(), existing.episode == snapshot.episode {
            if TopShelfFreshness.isStale(existing.updatedAt, now: snapshot.updatedAt) {
                try save(snapshot)
            }
            return false
        }
        try save(snapshot)
        return true
    }

    public func bannerURL(scale: Int, matching guid: String) -> URL? {
        guard bannerGUID() == guid else { return nil }
        let url = directory.appendingPathComponent(scale == 2 ? TopShelf.banner2xFileName : TopShelf.banner1xFileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    public func bannerGUID() -> String? {
        let url = directory.appendingPathComponent(TopShelf.bannerGUIDFileName)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public func writeBanners(scale1: Data, scale2: Data, guid: String) throws {
        guard !guid.isEmpty, !scale1.isEmpty, !scale2.isEmpty else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try scale1.write(to: directory.appendingPathComponent(TopShelf.banner1xFileName), options: .atomic)
        try scale2.write(to: directory.appendingPathComponent(TopShelf.banner2xFileName), options: .atomic)
        try Data(guid.utf8).write(to: directory.appendingPathComponent(TopShelf.bannerGUIDFileName), options: .atomic)
    }

    public func isArtworkPending() -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(TopShelf.pendingArtworkFileName).path)
    }

    public func setArtworkPending(_ pending: Bool) throws {
        let url = directory.appendingPathComponent(TopShelf.pendingArtworkFileName)
        if pending {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("1".utf8).write(to: url, options: .atomic)
        } else if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
