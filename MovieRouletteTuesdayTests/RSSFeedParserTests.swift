import XCTest
@testable import MovieRouletteTuesday

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
