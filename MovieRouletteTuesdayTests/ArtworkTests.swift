import XCTest
@testable import MovieRouletteTuesday
import MRTCore

final class ArtworkTests: XCTestCase {
    private let showArt = URL(string: "https://storage.buzzsprout.com/0ivqancdb8l9ww2mlieeag1x8bdr?.jpg")!

    // MARK: RSS parsing

    func testParsesItemAndChannelItunesImage() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/feed-snippet.xml")
        let url = Bundle(for: ArtworkTests.self).url(forResource: "feed-snippet", withExtension: "xml") ?? fixture
        let feed = try RSSFeedParser.parse(data: Data(contentsOf: url))
        XCTAssertEqual(feed.artworkURL, showArt)
        XCTAssertEqual(feed.episodes.map(\.imageURL), [
            URL(string: "https://storage.buzzsprout.com/owoiwvlyear05oze07ippg1m06yb?.jpg"),
            URL(string: "https://storage.buzzsprout.com/nwtsb7kutu2ctjeik3u8qmofhjkt?.jpg"),
        ])
    }

    func testItemWithoutImageDoesNotInheritPreviousOrChannelImage() throws {
        let xml = """
        <rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel>
        <title>Show</title>
        <image><url>https://example.com/rss-image.png</url><title>Show image</title></image>
        <item><title>A</title><guid>g1</guid><itunes:image href=" https://example.com/a.jpg "/></item>
        <item><title>B</title><guid>g2</guid></item>
        <item><title>C</title><guid>g3</guid><itunes:image href="javascript:alert(1)"/></item>
        <item><title>D</title><guid>g4</guid><itunes:image href=""/></item>
        </channel></rss>
        """
        let feed = try RSSFeedParser.parse(string: xml)
        XCTAssertEqual(feed.title, "Show", "the <image><title> must not replace the channel title")
        XCTAssertEqual(feed.episodes.map(\.imageURL), [URL(string: "https://example.com/a.jpg"), nil, nil, nil])
        // No channel itunes:image -> RSS <image><url> fallback.
        XCTAssertEqual(feed.artworkURL, URL(string: "https://example.com/rss-image.png"))
    }

    func testChannelItunesImageBeatsRSSImageAndFeedWithoutArtIsNil() throws {
        let both = """
        <rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel><title>S</title>
        <image><url>https://example.com/small.png</url></image>
        <itunes:image href="https://example.com/big.jpg"/>
        <item><title>A</title><guid>g1</guid></item></channel></rss>
        """
        XCTAssertEqual(try RSSFeedParser.parse(string: both).artworkURL, URL(string: "https://example.com/big.jpg"))
        let none = "<rss><channel><title>S</title><item><title>A</title><guid>g1</guid></item></channel></rss>"
        let feed = try RSSFeedParser.parse(string: none)
        XCTAssertNil(feed.artworkURL)
        XCTAssertNil(feed.episodes.first?.imageURL)
    }

    // MARK: Cache migration

    func testOldCacheWithoutArtworkStillDecodes() throws {
        let old = """
        {"fetchedAt": 700000000, "title": "Show", "episodes": [
          {"guid": "Buzzsprout-1", "title": "Old", "summary": "s", "season": 1, "episode": 2}
        ]}
        """
        let cache = try JSONDecoder().decode(CachedEpisodeFeed.self, from: Data(old.utf8))
        XCTAssertEqual(cache.episodes.count, 1)
        XCTAssertNil(cache.artworkURL)
        XCTAssertNil(cache.episodes[0].imageURL)
    }

    func testCacheRoundTripKeepsArtwork() throws {
        let ep = PodcastEpisode(guid: "g", title: "T", imageURL: URL(string: "https://example.com/e.jpg"))
        let cache = CachedEpisodeFeed(fetchedAt: Date(timeIntervalSince1970: 0), title: "S", episodes: [ep], artworkURL: showArt)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mrt-art-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try EpisodeFeedIO.saveCache(cache, to: url)
        XCTAssertEqual(try EpisodeFeedIO.loadCache(from: url), cache)
    }

    // MARK: Movie -> artwork resolution

    private func episode(_ guid: String, _ image: String?, day: Double?) -> PodcastEpisode {
        PodcastEpisode(guid: guid, title: guid, pubDate: day.map { Date(timeIntervalSince1970: $0 * 86_400) },
                       imageURL: image.flatMap(URL.init(string:)))
    }

    func testMovieUsesEarliestEpisodeWithArt() {
        let movie = Movie(id: "m", title: "M", year: 2000, genre: "Horror", episodeIds: ["late", "noart", "early", "missing"])
        let byGUID = PodcastEpisode.byGUID([
            episode("late", "https://example.com/late.jpg", day: 20),
            episode("noart", nil, day: 1),
            episode("early", "https://example.com/early.jpg", day: 10),
        ])
        let picked = ArtworkResolver.episodeArtwork(for: movie, episodesByGUID: byGUID)
        XCTAssertEqual(picked?.guid, "early")
        XCTAssertEqual(ArtworkResolver.candidates(for: movie, episodesByGUID: byGUID, showArtwork: showArt),
                       [URL(string: "https://example.com/early.jpg")!, showArt])
    }

    func testUndatedEpisodesComeAfterDatedOnesInCatalogOrder() {
        let movie = Movie(id: "m", title: "M", year: 2000, genre: "Horror", episodeIds: ["u1", "u2", "dated"])
        let byGUID = PodcastEpisode.byGUID([
            episode("u1", "https://example.com/u1.jpg", day: nil),
            episode("u2", "https://example.com/u2.jpg", day: nil),
            episode("dated", "https://example.com/d.jpg", day: 5),
        ])
        XCTAssertEqual(ArtworkResolver.episodeArtwork(for: movie, episodesByGUID: byGUID)?.guid, "dated")
        let undatedOnly = Movie(id: "m2", title: "M", year: 2000, genre: "Horror", episodeIds: ["u2", "u1"])
        XCTAssertEqual(ArtworkResolver.episodeArtwork(for: undatedOnly, episodesByGUID: byGUID)?.guid, "u2")
    }

    func testFallsBackToPosterThenShowThenPlaceholder() {
        let poster = URL(string: "https://example.com/poster.jpg")!
        let withPoster = Movie(id: "m", title: "M", year: 2000, genre: "Drama", episodeIds: ["x"], posterURL: poster)
        XCTAssertEqual(ArtworkResolver.candidates(for: withPoster, episodesByGUID: [:], showArtwork: showArt), [poster, showArt])
        let bare = Movie(id: "b", title: "B", year: 2000, genre: "Drama")
        XCTAssertEqual(ArtworkResolver.candidates(for: bare, episodesByGUID: [:], showArtwork: showArt), [showArt])
        XCTAssertEqual(ArtworkResolver.candidates(for: bare, episodesByGUID: [:], showArtwork: nil), [])
        // Same URL twice is tried once; unsafe schemes are dropped.
        let dup = Movie(id: "d", title: "D", year: 2000, genre: "Drama", posterURL: showArt)
        XCTAssertEqual(ArtworkResolver.candidates(for: dup, episodesByGUID: [:], showArtwork: showArt), [showArt])
        XCTAssertNil(ArtworkResolver.usableURL(URL(string: "file:///etc/passwd")))
        XCTAssertNil(ArtworkResolver.usableURL("not a url"))
    }

    func testEpisodeCandidates() {
        let ep = episode("g", "https://example.com/g.jpg", day: 1)
        XCTAssertEqual(ArtworkResolver.candidates(for: ep, showArtwork: showArt), [URL(string: "https://example.com/g.jpg")!, showArt])
        XCTAssertEqual(ArtworkResolver.candidates(for: episode("n", nil, day: 1), showArtwork: showArt), [showArt])
    }

    func testCatalogMoviesResolveAgainstFeedSnippet() throws {
        // End-to-end with the real fixture: a movie pointing at the snippet's first guid gets its art.
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/feed-snippet.xml")
        let url = Bundle(for: ArtworkTests.self).url(forResource: "feed-snippet", withExtension: "xml") ?? fixture
        let feed = try RSSFeedParser.parse(data: Data(contentsOf: url))
        let movie = Movie(id: "the-outsiders-1983", title: "The Outsiders", year: 1983, genre: "Drama", episodeIds: ["Buzzsprout-19913482"])
        let urls = ArtworkResolver.candidates(for: movie, episodesByGUID: PodcastEpisode.byGUID(feed.episodes), showArtwork: feed.artworkURL)
        XCTAssertEqual(urls.first?.absoluteString, "https://storage.buzzsprout.com/owoiwvlyear05oze07ippg1m06yb?.jpg")
        XCTAssertEqual(urls.last, showArt)
    }

    // MARK: Sizing

    func testDownsampleSizes() {
        XCTAssertEqual(ArtworkSizing.maxPixelSize(points: 44, scale: 3), 132)
        XCTAssertEqual(ArtworkSizing.maxPixelSize(points: 320, scale: 3), 960)
        XCTAssertEqual(ArtworkSizing.maxPixelSize(points: 600, scale: 3), ArtworkSizing.maxPixels)
        XCTAssertEqual(ArtworkSizing.maxPixelSize(points: .nan, scale: 3), ArtworkSizing.minPixels)
        XCTAssertEqual(ArtworkSizing.maxPixelSize(points: 0, scale: 2), ArtworkSizing.minPixels)
        XCTAssertEqual(ArtworkSizing.decodedBytes(width: 132, height: 132), 69_696)
    }

    // MARK: Movies navigation state

    func testMoviesNavigationSurvivesSizeClassChanges() {
        let compact: [MoviesRoute] = [.movie("a"), .episode("g1")]
        let regular = MoviesNavigation.regular(fromCompactPath: compact)
        XCTAssertEqual(regular, .init(selectedMovieID: "a", detailPath: [.episode("g1")]))
        XCTAssertEqual(MoviesNavigation.compactPath(from: regular), compact)

        XCTAssertEqual(MoviesNavigation.regular(fromCompactPath: []), .init(selectedMovieID: nil))
        XCTAssertEqual(MoviesNavigation.compactPath(from: .init(selectedMovieID: nil, detailPath: [.episode("x")])), [])
        // Deepest movie wins.
        XCTAssertEqual(MoviesNavigation.regular(fromCompactPath: [.movie("a"), .episode("g"), .movie("b")]),
                       .init(selectedMovieID: "b"))
        XCTAssertNil(MoviesRoute.episode("g").movieID)
    }
}
