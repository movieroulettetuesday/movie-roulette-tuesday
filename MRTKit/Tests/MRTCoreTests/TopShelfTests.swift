import XCTest
import MRTCore

final class TopShelfTests: XCTestCase {
    private var utc: TimeZone { TimeZone(identifier: "UTC")! }
    private var enUS: Locale { Locale(identifier: "en_US") }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func episode(
        guid: String,
        title: String = "Passengers",
        season: Int? = 4,
        episode: Int? = 37,
        pubDate: Date? = nil,
        duration: TimeInterval? = 1 * 3600 + 23 * 60,
        summary: String = "Listener pick from Kevin. They talk about the film.",
        imageURL: URL? = URL(string: "https://example.com/ep.jpg")
    ) -> PodcastEpisode {
        PodcastEpisode(
            guid: guid,
            title: title,
            pubDate: pubDate,
            season: season,
            episode: episode,
            summary: summary,
            imageURL: imageURL,
            duration: duration
        )
    }

    func testLatestEpisodeWinsAndDeepLinkRoundTrips() throws {
        let older = episode(guid: "old", title: "Old Film", episode: 36, pubDate: date(2026, 9, 1))
        let latest = episode(guid: "Buzzsprout-19913482", pubDate: date(2026, 10, 27))
        let built = try XCTUnwrap(TopShelfEpisodeBuilder.make(
            episodes: [older, latest],
            showName: "Movie Roulette Tuesday: The Podcast",
            now: date(2026, 10, 28)
        ))
        XCTAssertEqual(built.guid, "Buzzsprout-19913482")
        XCTAssertEqual(built.title, "Passengers")
        XCTAssertEqual(built.seasonEpisodeLabel, "S4E37")
        XCTAssertTrue(built.isNew)
        XCTAssertEqual(built.listenerCredit, "Listener pick from Kevin")
        XCTAssertEqual(built.showName, "Movie Roulette Tuesday")
        XCTAssertEqual(built.sectionTitle, "NEW EPISODE · S4E37")
        XCTAssertEqual(built.deepLink.absoluteString, "mrt://episode/Buzzsprout-19913482")
        XCTAssertEqual(DeepLink(url: built.deepLink), .episode(guid: "Buzzsprout-19913482"))
    }

    func testDeepLinkEscapesAndTVRouteAcceptsIt() throws {
        let guid = "Buzzsprout 1/odd"
        let url = DeepLink.episode(guid: guid).url
        XCTAssertEqual(url.scheme, "mrt")
        XCTAssertEqual(url.host, "episode")
        XCTAssertEqual(DeepLink(url: url), .episode(guid: guid))
        // TVRootView.open switches on this and pushes the episode page.
        if case .episode(let parsed) = DeepLink(url: url) {
            XCTAssertEqual(parsed, guid)
        } else {
            XCTFail("expected an episode link")
        }
    }

    func testMovieTitleAndPosterBeatEpisodeArt() throws {
        let ep = episode(guid: "g1", title: "RSS title", pubDate: date(2026, 10, 27))
        let movie = Movie(
            id: "passengers-2016",
            title: "Passengers",
            year: 2016,
            genre: "Sci-Fi",
            episodeIds: ["g1"],
            posterURL: URL(string: "https://example.com/poster.jpg")
        )
        let catalog = MovieCatalog(categories: [], movies: [movie])
        let built = try XCTUnwrap(TopShelfEpisodeBuilder.make(
            episodes: [ep],
            catalog: catalog,
            showArtwork: URL(string: "https://example.com/show.jpg"),
            now: date(2026, 10, 28)
        ))
        XCTAssertEqual(built.title, "Passengers")
        XCTAssertEqual(built.imageURL, URL(string: "https://example.com/poster.jpg"))
        XCTAssertEqual(built.imageShape, .poster)
    }

    func testEpisodeArtWhenPosterMissingAndShowArtLast() throws {
        let ep = episode(guid: "g1", imageURL: URL(string: "https://cdn.example/ep.jpg"))
        let built = try XCTUnwrap(TopShelfEpisodeBuilder.make(
            episodes: [ep],
            showArtwork: URL(string: "https://cdn.example/show.jpg"),
            now: date(2026, 10, 28)
        ))
        XCTAssertEqual(built.imageURL, URL(string: "https://cdn.example/ep.jpg"))
        XCTAssertEqual(built.imageShape, .square)

        let noArt = episode(guid: "g2", imageURL: nil)
        let fallback = try XCTUnwrap(TopShelfEpisodeBuilder.make(
            episodes: [noArt],
            showArtwork: URL(string: "https://cdn.example/show.jpg"),
            now: date(2026, 10, 28)
        ))
        XCTAssertEqual(fallback.imageURL, URL(string: "https://cdn.example/show.jpg"))
        XCTAssertNil(TopShelfEpisodeBuilder.make(episodes: []))
        XCTAssertNil(TopShelfEpisodeBuilder.make(episodes: [PodcastEpisode(guid: "", title: "X")]))
    }

    func testNewBadgeWindowMatchesThreeWeeks() {
        let published = date(2026, 10, 7)
        XCTAssertTrue(TopShelfEpisodeBuilder.isNew(published, now: date(2026, 10, 27)))
        XCTAssertFalse(TopShelfEpisodeBuilder.isNew(published, now: date(2026, 10, 29)))
        XCTAssertFalse(TopShelfEpisodeBuilder.isNew(nil, now: date(2026, 10, 27)))
        let built = TopShelfEpisodeBuilder.make(
            episodes: [episode(guid: "g", pubDate: published, summary: "")],
            now: date(2026, 11, 20)
        )
        XCTAssertEqual(built?.isNew, false)
        XCTAssertEqual(built?.sectionTitle, "Latest Episode · S4E37")
    }

    func testCopyMatchesTheMockLines() {
        let when = date(2026, 10, 27)
        XCTAssertEqual(
            TopShelfCopy.metaLine(season: 4, episode: 37, pubDate: when, locale: enUS, timeZone: utc),
            "S4E37 · Oct 27, 2026"
        )
        XCTAssertEqual(TopShelfCopy.runtime(1 * 3600 + 23 * 60), "1 hr 23 min")
        XCTAssertEqual(TopShelfCopy.runtime(3600), "1 hr")
        XCTAssertEqual(TopShelfCopy.runtime(45 * 60), "45 min")
        XCTAssertEqual(TopShelfCopy.runtime(30), "1 min")
        XCTAssertNil(TopShelfCopy.runtime(0))
        XCTAssertEqual(
            TopShelfCopy.detailLine(listenerCredit: "Listener pick from Kevin", duration: 1 * 3600 + 23 * 60),
            "Listener pick from Kevin · 1 hr 23 min"
        )
        XCTAssertEqual(TopShelfCopy.detailLine(listenerCredit: nil, duration: 3600), "1 hr")
        XCTAssertNil(TopShelfCopy.detailLine(listenerCredit: nil, duration: nil))
    }

    func testListenerCreditRequiresAName() {
        XCTAssertEqual(TopShelfCopy.listenerCredit(in: "This week is a listener pick from Kevin."), "Listener pick from Kevin")
        XCTAssertEqual(TopShelfCopy.listenerCredit(in: "Kevin's listener pick: Passengers"), "Listener pick from Kevin")
        XCTAssertEqual(TopShelfCopy.listenerCredit(in: "O'Brien's listener pick"), "Listener pick from O'Brien")
        XCTAssertNil(TopShelfCopy.listenerCredit(in: "Matt's sister Kristen joins us for her listener pick."))
        XCTAssertNil(TopShelfCopy.listenerCredit(in: "listener pick from the group"))
        XCTAssertNil(TopShelfCopy.listenerCredit(in: "No credit here."))
        XCTAssertEqual(TopShelfCopy.shelfShowName(from: "Movie Roulette Tuesday: The Podcast"), "Movie Roulette Tuesday")
        XCTAssertEqual(TopShelfCopy.shelfShowName(from: "  "), "Movie Roulette Tuesday")
    }

    func testBannerLayoutIsTheWideLatestEpisodeMock() throws {
        let built = try XCTUnwrap(TopShelfEpisodeBuilder.make(
            episodes: [episode(guid: "g", pubDate: date(2026, 10, 27))],
            showName: "Movie Roulette Tuesday: The Podcast",
            now: date(2026, 10, 28)
        ))
        let layout = TopShelfBannerMetrics.layout(for: built, canvas: TopShelf.insetSize1x, locale: enUS, timeZone: utc)
        XCTAssertEqual(layout.canvas, TopShelfPixelSize(width: 1920, height: 720))
        XCTAssertLessThan(layout.poster.maxX, layout.textColumnX)
        XCTAssertGreaterThan(layout.poster.width, 0)
        XCTAssertLessThan(layout.poster.maxX, layout.canvas.width)
        XCTAssertEqual(layout.badgeText, "NEW EPISODE")
        XCTAssertTrue(layout.showsNewBadge)
        XCTAssertEqual(layout.metaLine, "S4E37 · Oct 27, 2026")
        XCTAssertEqual(layout.title, "Passengers")
        XCTAssertEqual(layout.detailLine, "Listener pick from Kevin · 1 hr 23 min")
        XCTAssertEqual(layout.showName, "Movie Roulette Tuesday")
        XCTAssertEqual(layout.titleFontSize, 92)

        let doubled = TopShelfBannerMetrics.layout(for: built, canvas: TopShelf.insetSize2x, locale: enUS, timeZone: utc)
        XCTAssertEqual(doubled.canvas, TopShelfPixelSize(width: 3840, height: 1440))
        XCTAssertEqual(doubled.poster.width, layout.poster.width * 2)
        XCTAssertEqual(doubled.titleFontSize, layout.titleFontSize * 2)
        XCTAssertEqual(TopShelf.staticWideSize, TopShelfPixelSize(width: 2320, height: 720))
    }

    func testContentPlanUsesInsetOnlyWhenTheBannerMatches() throws {
        let built = try XCTUnwrap(TopShelfEpisodeBuilder.make(
            episodes: [episode(guid: "g", pubDate: date(2026, 10, 27), summary: "")],
            now: date(2026, 10, 28)
        ))
        let sectioned = TopShelfContentPlan.make(episode: built, banner1x: nil, banner2x: nil)
        XCTAssertEqual(sectioned.style, .sectioned)
        XCTAssertEqual(sectioned.imageShape, .square)
        XCTAssertEqual(sectioned.imageURL, built.imageURL)
        XCTAssertEqual(sectioned.deepLink, built.deepLink)
        XCTAssertEqual(sectioned.sectionTitle, "NEW EPISODE · S4E37")

        let banner = URL(fileURLWithPath: "/tmp/topshelf-banner-1x.png")
        let banner2 = URL(fileURLWithPath: "/tmp/topshelf-banner-2x.png")
        let inset = TopShelfContentPlan.make(episode: built, banner1x: banner, banner2x: banner2)
        XCTAssertEqual(inset.style, .inset)
        XCTAssertEqual(inset.imageShape, .hdtv)
        XCTAssertEqual(inset.imageURL, banner)
        XCTAssertEqual(inset.imageURL2x, banner2)
    }

    func testSnapshotStoreRoundTripBannerGuidAndFreshness() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TopShelfSnapshotStore(directory: dir)
        XCTAssertNil(store.load())
        XCTAssertNil(store.bannerURL(scale: 1, matching: "g"))

        let episode = TopShelfEpisode(guid: "g", title: "Passengers", showName: "Movie Roulette Tuesday")
        let first = date(2026, 10, 27, hour: 12)
        XCTAssertTrue(try store.saveIfChanged(TopShelfSnapshot(episode: episode, updatedAt: first)))
        XCTAssertFalse(try store.saveIfChanged(TopShelfSnapshot(episode: episode, updatedAt: first.addingTimeInterval(60))))
        XCTAssertEqual(store.load()?.updatedAt, first, "a fresh duplicate does not rewrite")

        let staleNow = first.addingTimeInterval(TopShelf.staleAfter)
        XCTAssertTrue(TopShelfFreshness.isStale(first, now: staleNow))
        XCTAssertEqual(TopShelfLoadPlan.decide(snapshot: store.load(), now: staleNow), .refresh)
        XCTAssertFalse(try store.saveIfChanged(TopShelfSnapshot(episode: episode, updatedAt: staleNow)))
        XCTAssertEqual(store.load()?.updatedAt, staleNow, "confirming the same episode refreshes the timestamp")
        XCTAssertEqual(TopShelfLoadPlan.decide(snapshot: store.load(), now: staleNow), .useCache)
        XCTAssertEqual(TopShelfLoadPlan.decide(snapshot: nil, now: staleNow), .refresh)

        let renamed = TopShelfEpisode(guid: "g", title: "Passengers (2016)", showName: "Movie Roulette Tuesday")
        XCTAssertTrue(try store.saveIfChanged(TopShelfSnapshot(episode: renamed, updatedAt: staleNow)))
        XCTAssertEqual(store.load()?.episode.title, "Passengers (2016)")

        try store.writeBanners(scale1: Data("one".utf8), scale2: Data("two".utf8), guid: "g")
        XCTAssertEqual(store.bannerGUID(), "g")
        XCTAssertNotNil(store.bannerURL(scale: 1, matching: "g"))
        XCTAssertNotNil(store.bannerURL(scale: 2, matching: "g"))
        XCTAssertNil(store.bannerURL(scale: 1, matching: "other"))
        XCTAssertFalse(store.isArtworkPending())
        try store.setArtworkPending(true)
        XCTAssertTrue(store.isArtworkPending())
        try store.setArtworkPending(false)
        XCTAssertFalse(store.isArtworkPending())

        try Data("junk".utf8).write(to: store.fileURL)
        XCTAssertNil(store.load())
    }
}
