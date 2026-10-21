import XCTest
@testable import MovieRouletteTuesday
import MRTCore

final class RSSFeedParserTests: XCTestCase {
    private var fixtureURL: URL {
        // Prefer test-bundle resource; fall back to source-relative path (Linux / swift test).
        if let url = Bundle(for: RSSFeedParserTests.self).url(forResource: "feed-snippet", withExtension: "xml") {
            return url
        }
        if let url = Bundle.main.url(forResource: "feed-snippet", withExtension: "xml") {
            return url
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/feed-snippet.xml")
    }

    func testParsesBuzzsproutSnippet() throws {
        let data = try Data(contentsOf: fixtureURL)
        let feed = try RSSFeedParser.parse(data: data)
        XCTAssertFalse(feed.title.isEmpty)
        XCTAssertEqual(feed.episodes.count, 2)

        let first = feed.episodes[0]
        XCTAssertEqual(first.title, "The Outsiders")
        XCTAssertEqual(first.guid, "Buzzsprout-19913482")
        XCTAssertEqual(first.season, 4)
        XCTAssertEqual(first.episode, 34)
        XCTAssertEqual(first.episodeType, "full")
        XCTAssertNotNil(first.pubDate)
        XCTAssertFalse(first.summary.isEmpty)
        XCTAssertFalse(first.summary.contains("<p>"))
        // Full show notes, not Buzzsprout's 500-char itunes:summary ("...").
        XCTAssertGreaterThan(first.summary.count, 500)
        XCTAssertFalse(first.summary.hasSuffix("..."))
        XCTAssertFalse(first.summary.lowercased().hasPrefix("send us fan mail"))
        XCTAssertNotNil(first.fanMailURL)

        let second = feed.episodes[1]
        XCTAssertEqual(second.title, "The Ugly Stepsister")
        XCTAssertEqual(second.guid, "Buzzsprout-19877460")
        XCTAssertEqual(second.season, 4)
        XCTAssertEqual(second.episode, 33)
    }

    func testEmptyDataThrows() {
        XCTAssertThrowsError(try RSSFeedParser.parse(data: Data())) { error in
            XCTAssertEqual(error as? RSSFeedError, .emptyDocument)
        }
    }

    func testEmptyChannelYieldsNoEpisodes() throws {
        // XMLParser is lenient with junk tags; an empty channel is the realistic "parsed but unused" case.
        let feed = try RSSFeedParser.parse(string: """
            <?xml version="1.0"?><rss version="2.0"><channel><title>Empty</title></channel></rss>
            """)
        XCTAssertEqual(feed.title, "Empty")
        XCTAssertEqual(feed.episodes.count, 0)
    }

    // TestFlight 1.0 (4): show notes began with "Send us Fan Mail" as plain text.
    func testFanMailLineIsStrippedAndOfferedAsLink() throws {
        let feed = try RSSFeedParser.parse(data: Data(contentsOf: fixtureURL))
        for ep in feed.episodes {
            XCTAssertFalse(ep.summary.lowercased().hasPrefix("send us fan mail"), ep.summary)
            XCTAssertEqual(ep.fanMailURL?.absoluteString, "https://www.buzzsprout.com/2117292/fan_mail/new")
        }
        XCTAssertTrue(feed.episodes[0].summary.hasPrefix("Hi everyone"))
    }

    func testShowNotesHelpers() {
        XCTAssertEqual(ShowNotes.strippingFanMail("Send us Fan Mail Hi there"), "Hi there")
        XCTAssertEqual(ShowNotes.strippingFanMail("send us fanmail: Hi"), "Hi")
        XCTAssertEqual(ShowNotes.strippingFanMail("We read fan mail today"), "We read fan mail today")
        XCTAssertEqual(ShowNotes.strippingFanMail("Send us Fan Mail"), "")
        XCTAssertNil(ShowNotes.fanMailURL(inHTML: "<p>No link</p>"))
        XCTAssertNil(ShowNotes.fanMailURL(inHTML: #"<a href="https://example.com/x">Other</a>"#))
        XCTAssertEqual(
            ShowNotes.fanMailURL(inHTML: #"<p><a target="_blank" href="https://www.buzzsprout.com/1/fan_mail/new">Send us Fan Mail</a></p>"#)?.absoluteString,
            "https://www.buzzsprout.com/1/fan_mail/new")
        // Summaries cached by older builds are cleaned at display time.
        XCTAssertEqual(PodcastEpisode(guid: "g", title: "t", summary: "Send us Fan Mail Hello").displaySummary, "Hello")
    }

    func testOldCacheWithoutFanMailURLDecodes() throws {
        let json = #"{"guid":"g","title":"t","summary":"s"}"#
        let ep = try JSONDecoder().decode(PodcastEpisode.self, from: Data(json.utf8))
        XCTAssertNil(ep.fanMailURL)
    }
}


final class EpisodeGroupingTests: XCTestCase {
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private func date(_ y: Int, _ m: Int) -> Date { utc.date(from: DateComponents(year: y, month: m, day: 15))! }

    private var episodes: [PodcastEpisode] {
        [
            PodcastEpisode(guid: "e5", title: "S3 new", pubDate: date(2026, 9), season: 3, episode: 2),
            PodcastEpisode(guid: "b1", title: "Bonus", pubDate: date(2026, 5)),
            PodcastEpisode(guid: "e4", title: "S3 first", pubDate: date(2026, 1), season: 3, episode: 1),
            PodcastEpisode(guid: "e3", title: "S2", pubDate: date(2025, 6), season: 2, episode: 1),
            PodcastEpisode(guid: "e1", title: "S1", pubDate: date(2024, 3), season: 1, episode: 1),
            PodcastEpisode(guid: "x", title: "Undated, no season"),
        ]
    }

    func testBySeasonNewestFirstBonusLast() {
        let g = EpisodeGrouper.groups(episodes, by: .season, calendar: utc)
        XCTAssertEqual(g.map(\.id), ["season-3", "season-2", "season-1", "bonus"])
        XCTAssertEqual(g.map(\.title), ["Season 3", "Season 2", "Season 1", "Bonus"])
        XCTAssertEqual(g[0].episodes.map(\.guid), ["e5", "e4"], "feed order kept")
        XCTAssertEqual(g[3].episodes.map(\.guid), ["b1", "x"])
        XCTAssertEqual(g.map(\.episodes.count).reduce(0, +), episodes.count)
    }

    func testByYearPutsUnseasonedUnderTheirYear() {
        let g = EpisodeGrouper.groups(episodes, by: .year, calendar: utc)
        XCTAssertEqual(g.map(\.id), ["year-2026", "year-2025", "year-2024", "undated"])
        XCTAssertEqual(g[0].episodes.map(\.guid), ["e5", "b1", "e4"])
        XCTAssertEqual(g[3].episodes.map(\.guid), ["x"])
    }

    func testAllAndEmpty() {
        XCTAssertEqual(EpisodeGrouper.groups(episodes, by: .all).first?.episodes.count, episodes.count)
        XCTAssertTrue(EpisodeGrouper.groups([], by: .season).isEmpty)
        XCTAssertTrue(EpisodeGrouper.groups([], by: .all).isEmpty)
    }

    func testExpansionDefaultsAndPersistence() {
        var e = EpisodeGroupExpansion(serialized: "")
        XCTAssertTrue(e.isExpanded("season-3", isNewest: true), "newest group starts open")
        XCTAssertFalse(e.isExpanded("season-2", isNewest: false))
        e.toggle("season-3", isNewest: true)
        e.toggle("season-1", isNewest: false)
        XCTAssertEqual(e.serialized, "season-1:1,season-3:0")
        let restored = EpisodeGroupExpansion(serialized: e.serialized)
        XCTAssertFalse(restored.isExpanded("season-3", isNewest: true))
        XCTAssertTrue(restored.isExpanded("season-1", isNewest: false))
        XCTAssertEqual(EpisodeGroupExpansion(serialized: "junk,:1,a:1:2,b:0").states, ["b": false])
    }
}
