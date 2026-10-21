import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(FoundationXML)
import FoundationXML
#endif

public struct PodcastFeed: Equatable, Sendable {
    public var title: String
    public var episodes: [PodcastEpisode]
    /// Show artwork: channel `<itunes:image href>`, else RSS `<image><url>`.
    public var artworkURL: URL?

    public init(title: String = "", episodes: [PodcastEpisode] = [], artworkURL: URL? = nil) {
        self.title = title
        self.episodes = episodes
        self.artworkURL = artworkURL
    }
}

public enum RSSFeedError: Error, LocalizedError, Equatable {
    case emptyDocument
    case malformed
    /// Parsed, but no episodes (captive portal / outage page / empty channel).
    case noEpisodes

    public var errorDescription: String? {
        switch self {
        case .emptyDocument: return "The feed was empty."
        case .malformed: return "The feed could not be parsed."
        case .noEpisodes: return "The feed had no episodes."
        }
    }
}

/// Minimal RSS 2.0 + iTunes podcast parser (no third-party deps).
///
/// Handles the Buzzsprout fields we need: title, guid, pubDate, link,
/// description / itunes:summary, itunes:season, itunes:episode, itunes:episodeType,
/// itunes:image (per item and per channel).
public enum RSSFeedParser {
    /// The longest of the candidate show-notes texts (description, content:encoded,
    /// itunes:summary), so a truncated itunes:summary never wins.
    static func fullestNotes(_ candidates: [String]) -> String {
        candidates.max { $0.count < $1.count } ?? ""
    }

    public static func parse(data: Data) throws -> PodcastFeed {
        guard !data.isEmpty else { throw RSSFeedError.emptyDocument }
        let delegate = FeedDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw delegate.error ?? RSSFeedError.malformed
        }
        return PodcastFeed(
            title: delegate.channelTitle,
            episodes: PodcastEpisode.uniqued(delegate.episodes),
            artworkURL: ArtworkResolver.usableURL(delegate.channelImage)
                ?? ArtworkResolver.usableURL(delegate.channelImageFallback)
        )
    }

    /// RFC 822 pubDate, tolerating the common variants seen in the wild
    /// (no weekday, no seconds, named zones like "GMT"/"EST"). Unparseable -> nil.
    public static func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for formatter in dateFormatters.all {
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }

    /// DateFormatter is thread-safe for parsing on Apple platforms (iOS 7+);
    /// these are configured once and never mutated afterwards.
    private final class Formatters: @unchecked Sendable {
        let all: [DateFormatter] = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "dd MMM yyyy HH:mm:ss Z",
            "dd MMM yyyy HH:mm:ss zzz",
            "EEE, dd MMM yyyy HH:mm Z",
            "EEE, dd MMM yyyy HH:mm zzz",
        ].map { format in
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(secondsFromGMT: 0)
            f.dateFormat = format
            return f
        }
    }

    private static let dateFormatters = Formatters()

    public static func parse(string: String) throws -> PodcastFeed {
        try parse(data: Data(string.utf8))
    }
}

// XMLParserDelegate must be a class; kept fileprivate to the parser.
private final class FeedDelegate: NSObject, XMLParserDelegate {
    var channelTitle = ""
    /// Channel `<itunes:image href>` (first one wins).
    var channelImage = ""
    /// Channel RSS `<image><url>` — used only when there's no itunes:image.
    var channelImageFallback = ""
    var episodes: [PodcastEpisode] = []
    var error: Error?

    private var path: [String] = []
    private var text = ""
    private var itemTitle = ""
    private var itemGUID = ""
    private var itemLink = ""
    private var itemPubDate = ""
    private var itemDescription = ""
    private var itemSummary = ""
    private var itemSeason = ""
    private var itemEpisode = ""
    private var itemEpisodeType = ""
    private var itemImage = ""
    private var itemHTML = ""
    private var inItem = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = Self.localName(elementName)
        path.append(name)
        text = ""
        if name == "item" {
            inItem = true
            itemTitle = ""; itemGUID = ""; itemLink = ""; itemPubDate = ""
            itemDescription = ""; itemSeason = ""; itemEpisode = ""; itemEpisodeType = ""
            itemImage = ""; itemHTML = ""; itemSummary = ""
        }
        // itunes:image carries the URL in an attribute (`href`); RSS <image> has none.
        if name == "image", let href = attributeDict["href"] ?? attributeDict["HREF"] {
            let value = href.trimmingCharacters(in: .whitespacesAndNewlines)
            if inItem {
                if itemImage.isEmpty { itemImage = value }
            } else if path.contains("channel"), channelImage.isEmpty {
                channelImage = value
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let s = String(data: CDATABlock, encoding: .utf8) { text += s }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = Self.localName(elementName)
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if inItem {
            switch name {
            case "title": itemTitle = value
            case "guid": itemGUID = value
            case "link": itemLink = value
            case "pubdate": itemPubDate = value
            case "summary":
                // Buzzsprout caps itunes:summary at 500 chars ("…b..."), so it is only
                // a fallback; the full show notes come from description/content:encoded.
                if !value.isEmpty { itemSummary = value }
            case "description":
                if itemDescription.isEmpty { itemDescription = value }
                if itemHTML.isEmpty { itemHTML = value }
            case "encoded":
                if itemHTML.isEmpty { itemHTML = value }
            case "season": itemSeason = value
            case "episode":
                if Int(value) != nil { itemEpisode = value }
            case "episodetype": itemEpisodeType = value
            case "item":
                let guid = itemGUID.isEmpty ? itemLink : itemGUID
                if !guid.isEmpty, !itemTitle.isEmpty {
                    episodes.append(PodcastEpisode(
                        guid: guid,
                        title: itemTitle,
                        pubDate: RSSFeedParser.parseDate(itemPubDate),
                        link: URL(string: itemLink),
                        season: Int(itemSeason),
                        episode: Int(itemEpisode),
                        episodeType: itemEpisodeType.isEmpty ? nil : itemEpisodeType,
                        summary: RSSFeedParser.fullestNotes(
                            [itemDescription, itemHTML, itemSummary].map { ShowNotes.strippingFanMail(stripHTML($0)) }
                        ),
                        imageURL: ArtworkResolver.usableURL(itemImage),
                        fanMailURL: ShowNotes.fanMailURL(inHTML: itemHTML)
                    ))
                }
                inItem = false
            default: break
            }
        } else if name == "title", path.contains("channel"), !path.contains("item"), !path.contains("image") {
            if channelTitle.isEmpty { channelTitle = value }
        } else if name == "url", path.contains("channel"), path.dropLast().last == "image" {
            if channelImageFallback.isEmpty { channelImageFallback = value }
        }

        if !path.isEmpty { path.removeLast() }
        text = ""
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        error = parseError
    }

    /// "itunes:season" / "Season" → "season"
    private static func localName(_ elementName: String) -> String {
        let lower = elementName.lowercased()
        if let idx = lower.lastIndex(of: ":") {
            return String(lower[lower.index(after: idx)...])
        }
        return lower
    }
}

private func stripHTML(_ html: String) -> String {
    var s = html
    // Cheap unescape / tag strip — enough for Buzzsprout blurbs in a list cell.
    s = s.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
    let entities: [(String, String)] = [
        ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
        ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " "),
    ]
    for (a, b) in entities { s = s.replacingOccurrences(of: a, with: b) }
    s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    return s.trimmingCharacters(in: .whitespacesAndNewlines)
}

extension PodcastEpisode {
    /// Drops repeated guids (keeping the first occurrence). A feed or an old
    /// cache with duplicate guids must never crash dictionary building or
    /// confuse SwiftUI list identity.
    public static func uniqued(_ episodes: [PodcastEpisode]) -> [PodcastEpisode] {
        var seen = Set<String>()
        return episodes.filter { seen.insert($0.guid).inserted }
    }

    /// guid -> episode, first occurrence wins (never traps on duplicates).
    public static func byGUID(_ episodes: [PodcastEpisode]) -> [String: PodcastEpisode] {
        Dictionary(episodes.map { ($0.guid, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
