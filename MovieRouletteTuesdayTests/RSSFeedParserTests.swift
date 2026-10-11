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
}
