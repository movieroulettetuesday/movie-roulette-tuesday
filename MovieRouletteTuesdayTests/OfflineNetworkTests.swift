import XCTest
@testable import MovieRouletteTuesday

/// Backlog item 6: offline, slow, timeout, and recovery for the four
/// networked surfaces — without touching the host or simulator network
/// settings. Catalog and CloudKit use injectable fakes; the RSS fetch uses
/// a `URLProtocol` stub on a private `URLSession`.
///
/// Where to Watch is not a live TMDB request: provider data is baked into
/// `movies.json` and arrives with the catalog. These tests treat a catalog
/// timeout as the Where to Watch "network" case, and assert empty / missing
/// streaming states on the display model.
final class OfflineNetworkTests: XCTestCase {

    // MARK: - URLProtocol stub (RSS)

    /// Thread-safe script of responses, keyed by host "offline-net.stub".
    final class ScriptedProtocol: URLProtocol, @unchecked Sendable {
        struct Reply: Sendable {
            var error: URLError?
            var status: Int = 200
            var body: Data = Data()
            var delay: TimeInterval = 0
        }
        nonisolated(unsafe) static var replies: [String: Reply] = [:]
        nonisolated(unsafe) static var hits: [String] = []
        private static let lock = NSLock()

        static func reset() {
            lock.lock(); replies = [:]; hits = []; lock.unlock()
        }
        static func set(_ path: String, _ reply: Reply) {
            lock.lock(); replies[path] = reply; lock.unlock()
        }
        static func recordedHits() -> [String] {
            lock.lock(); defer { lock.unlock() }; return hits
        }

        override class func canInit(with request: URLRequest) -> Bool {
            request.url?.host == "offline-net.stub"
        }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let path = request.url?.path ?? ""
            Self.lock.lock()
            Self.hits.append(path)
            let reply = Self.replies[path]
            Self.lock.unlock()
            guard let reply else {
                client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
                return
            }
            if reply.delay > 0 { Thread.sleep(forTimeInterval: reply.delay) }
            if let error = reply.error {
                client?.urlProtocol(self, didFailWithError: error)
                return
            }
            let url = request.url!
            let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/rss+xml"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: reply.body)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private static let oneEpisodeRSS = Data("""
        <?xml version="1.0"?><rss version="2.0"><channel><title>Show</title>\
        <item><guid>Buzzsprout-recovery</guid><title>Recovery</title></item>\
        </channel></rss>
        """.utf8)

    private var session: URLSession!
    private var cacheURL: URL!
    private var dir: URL!

    override func setUpWithError() throws {
        ScriptedProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScriptedProtocol.self]
        config.timeoutIntervalForRequest = 2
        session = URLSession(configuration: config)

        dir = FileManager.default.temporaryDirectory.appendingPathComponent("mrt-offline-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        cacheURL = dir.appendingPathComponent("episodes-cache.json")
        let cached = CachedEpisodeFeed(
            fetchedAt: Date(timeIntervalSince1970: 800_000_000),
            title: "Show",
            episodes: [PodcastEpisode(guid: "Buzzsprout-cached", title: "Cached Episode")]
        )
        try EpisodeFeedIO.saveCache(cached, to: cacheURL)
    }

    override func tearDownWithError() throws {
        session.invalidateAndCancel()
        try? FileManager.default.removeItem(at: dir)
        ScriptedProtocol.reset()
    }

    private func feedURL(_ path: String) -> URL { URL(string: "https://offline-net.stub\(path)")! }

    private func refresh(_ path: String) async throws -> CachedEpisodeFeed {
        try await EpisodeFeedIO.refresh(from: feedURL(path), cacheURL: cacheURL, session: session)
    }

    private func cacheBytes() throws -> Data { try Data(contentsOf: cacheURL) }

    // MARK: RSS — offline, timeout, slow, recovery

    func testRSSOfflineLeavesCacheAndSurfacesFriendlyMessage() async throws {
        let before = try cacheBytes()
        ScriptedProtocol.set("/feed.rss", .init(error: URLError(.notConnectedToInternet)))
        do {
            _ = try await refresh("/feed.rss")
            XCTFail("offline RSS must throw")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
            let message = await EpisodeStore.friendlyMessage(for: error)
            XCTAssertEqual(message, "You’re offline. Showing saved episodes.")
        }
        XCTAssertEqual(try cacheBytes(), before)
        XCTAssertEqual(try EpisodeFeedIO.loadCache(from: cacheURL).episodes.map(\.guid), ["Buzzsprout-cached"])
    }

    func testRSSTimeoutLeavesCacheAndSurfacesFriendlyMessage() async throws {
        let before = try cacheBytes()
        ScriptedProtocol.set("/slow.rss", .init(error: URLError(.timedOut)))
        do {
            _ = try await refresh("/slow.rss")
            XCTFail("timed-out RSS must throw")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
            let message = await EpisodeStore.friendlyMessage(for: error)
            XCTAssertEqual(message, "Loading episodes took too long. Pull down to try again.")
        }
        XCTAssertEqual(try cacheBytes(), before)
    }

    func testRSSSlowSuccessStillReplacesCache() async throws {
        ScriptedProtocol.set("/slow-ok.rss", .init(body: Self.oneEpisodeRSS, delay: 0.05))
        let fresh = try await refresh("/slow-ok.rss")
        XCTAssertEqual(fresh.episodes.map(\.guid), ["Buzzsprout-recovery"])
        XCTAssertEqual(try EpisodeFeedIO.loadCache(from: cacheURL).episodes.map(\.guid), ["Buzzsprout-recovery"])
    }

    func testRSSRecoversWhenTheNetworkComesBack() async throws {
        let before = try cacheBytes()
        ScriptedProtocol.set("/flaky.rss", .init(error: URLError(.notConnectedToInternet)))
        do { _ = try await refresh("/flaky.rss"); XCTFail("expected offline") } catch {}
        XCTAssertEqual(try cacheBytes(), before)

        ScriptedProtocol.set("/flaky.rss", .init(body: Self.oneEpisodeRSS))
        let fresh = try await refresh("/flaky.rss")
        XCTAssertEqual(fresh.episodes.map(\.guid), ["Buzzsprout-recovery"])
        XCTAssertEqual(try EpisodeFeedIO.loadCache(from: cacheURL).episodes.map(\.guid), ["Buzzsprout-recovery"])
        XCTAssertEqual(ScriptedProtocol.recordedHits(), ["/flaky.rss", "/flaky.rss"])
    }

    func testRSSOfflineWithNoCacheDoesNotInventEpisodes() async {
        try? FileManager.default.removeItem(at: cacheURL)
        ScriptedProtocol.set("/feed.rss", .init(error: URLError(.notConnectedToInternet)))
        do {
            _ = try await refresh("/feed.rss")
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }
        XCTAssertNil(try? EpisodeFeedIO.loadCache(from: cacheURL))
        let loaded = await EpisodeFeedIO.loadCacheIfPresent(from: cacheURL)
        XCTAssertNil(loaded)
    }

    // MARK: Catalog — timeout, slow, recovery (offline + bad remote already in RemoteCatalogTests)

    private func bundledURL() -> URL? {
        Bundle.main.url(forResource: "movies", withExtension: "json")
            ?? URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("MovieRouletteTuesday/Resources/movies.json")
    }

    private func bundled() throws -> MovieCatalog {
        let url = try XCTUnwrap(bundledURL())
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("no movies.json") }
        return try MovieCatalog.decode(from: Data(contentsOf: url))
    }

    private func catalogCache() -> CatalogCache {
        CatalogCache(fileURL: dir.appendingPathComponent("movies-remote-cache.json"), build: "test-offline")
    }

    func testCatalogTimeoutLeavesCacheAndFallsBackLocally() async throws {
        let good = try bundled()
        let cache = catalogCache()
        try cache.save(JSONEncoder().encode(good), fetchedAt: Date(timeIntervalSince1970: 1))
        let remote = RemoteCatalogSource(url: RemoteCatalog.url, timeout: 0.2) { _ in
            throw URLError(.timedOut)
        }
        do {
            _ = try await CatalogRefresher(remote: remote, cache: cache).refresh()
            XCTFail("catalog timeout must throw")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }
        XCTAssertEqual(cache.loadCatalog()?.movies.count, good.movies.count)
        let local = try await LocalCatalog.source(cache: cache, bundled: FileCatalogSource(fileURL: try XCTUnwrap(bundledURL()))).loadCatalog()
        XCTAssertEqual(local.movies.count, good.movies.count)
    }

    func testCatalogSlowSuccessThenRecoveryAfterTimeout() async throws {
        let good = try bundled()
        var extra = good
        extra.movies.append(Movie(id: "offline-recovery-2026", title: "Recovery Film", year: 2026, genre: "Horror",
                                  categories: ["cat-horror"], episodeIds: [], episodeTitle: "Recovery"))
        if let i = extra.categories.firstIndex(where: { $0.id == "cat-horror" }) {
            extra.categories[i].movieIds.append("offline-recovery-2026")
        }
        let body = try JSONEncoder().encode(extra)
        let cache = catalogCache()
        try cache.save(JSONEncoder().encode(good))

        actor Gate { var failFirst = true; func take() -> Bool { defer { failFirst = false }; return failFirst } }
        let gate = Gate()
        let remote = RemoteCatalogSource(url: RemoteCatalog.url) { _ in
            if await gate.take() { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(40))
            let response = HTTPURLResponse(url: RemoteCatalog.url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (body, response)
        }
        do { _ = try await CatalogRefresher(remote: remote, cache: cache).refresh(); XCTFail("first call times out") } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }
        XCTAssertNil(cache.loadCatalog()?.movie(withId: "offline-recovery-2026"), "timeout must not write")

        let recovered = try await CatalogRefresher(remote: remote, cache: cache).refresh()
        XCTAssertNotNil(recovered.movie(withId: "offline-recovery-2026"))
        XCTAssertNotNil(cache.loadCatalog()?.movie(withId: "offline-recovery-2026"))
    }

    // MARK: Where to Watch (catalog-backed, not a live TMDB call)

    func testWhereToWatchUsesBundledProvidersWhenCatalogRefreshFails() async throws {
        let bundled = try bundled()
        let withStreaming = try XCTUnwrap(bundled.movies.first(where: { $0.streaming != nil }),
                                          "bundled catalog has streaming data")
        let display = WhereToWatchDisplay(movie: withStreaming)
        XCTAssertTrue(display.showsProviders, "offline launch still shows bundled providers")
        XCTAssertFalse(display.showsEmptyMessage)
        XCTAssertNotNil(display.footer)

        let cache = catalogCache()
        try cache.save(JSONEncoder().encode(bundled))
        let remote = RemoteCatalogSource(url: RemoteCatalog.url) { _ in throw URLError(.timedOut) }
        do { _ = try await CatalogRefresher(remote: remote, cache: cache).refresh(); XCTFail("timeout") } catch {}
        let local = try XCTUnwrap(cache.loadCatalog())
        let after = WhereToWatchDisplay(movie: try XCTUnwrap(local.movie(withId: withStreaming.id)))
        XCTAssertEqual(after.showsProviders, display.showsProviders)
        XCTAssertEqual(after.link, display.link)
        XCTAssertEqual(after.footer, display.footer)
    }

    func testWhereToWatchEmptyAndMissingTmdbStates() {
        let noData = Movie(id: "no-stream", title: "No Stream", year: 1999, genre: "Drama",
                           categories: ["cat-horror"], episodeIds: [])
        let empty = WhereToWatchDisplay(movie: noData)
        XCTAssertFalse(empty.showsProviders)
        XCTAssertTrue(empty.showsEmptyMessage)
        XCTAssertEqual(WhereToWatchDisplay.emptyMessage, "No streaming sources found.")
        XCTAssertNil(empty.link, "no tmdb id and no providers: no TMDB link")
        XCTAssertNil(empty.footer)

        let withId = Movie(id: "no-stream", title: "No Stream", year: 1999, genre: "Drama",
                           categories: ["cat-horror"], episodeIds: [], tmdbId: 42)
        let linked = WhereToWatchDisplay(movie: withId)
        XCTAssertFalse(linked.showsProviders)
        XCTAssertTrue(linked.showsEmptyMessage)
        XCTAssertNotNil(linked.link, "a tmdb id still offers the All options page")
        XCTAssertNotNil(linked.footer, "the All options link still carries TMDB attribution")
    }

    // MARK: CloudKit listener ratings

    private actor FlakyRatingsStore: CommunityStore {
        var error: Error?
        var bulk: [String: ListenerRatingEntry] = [:]
        private(set) var calls = 0
        func fail(with error: Error?) { self.error = error }
        func seed(_ bulk: [String: ListenerRatingEntry]) { self.bulk = bulk }
        func fetchAllRatings(movieIds: [String]) async throws -> [String: ListenerRatingEntry] {
            calls += 1
            if let error { throw error }
            return bulk
        }
        func accountStatus() async -> CommunityAccountStatus { .available }
        func submitVote(pollId: String, option: String) async throws -> String { throw CommunityError.notSignedIn }
        func fetchVotes(pollId: String) async throws -> [String: String] { [:] }
        func myVote(pollId: String) async throws -> String? { nil }
        func submitRating(movieId: String, halfStars: Int) async throws -> String { throw CommunityError.notSignedIn }
        func fetchRatings(movieId: String) async throws -> [String: Int] { [:] }
        func myRating(movieId: String) async throws -> Int? { nil }
        func submitSuggestion(_ suggestion: InAppSuggestion, appVersion: String) async throws {}
        func callCount() -> Int { calls }
    }

    func testCloudKitTimeoutAndOfflineKeepCachedRatingsThenRecover() async throws {
        let cached = [
            "the-room-2003": RatingAggregate.from(halfStars: [8, 9]),
        ]
        let store = FlakyRatingsStore()
        await store.fail(with: URLError(.timedOut))
        var fetched: [String: RatingAggregate]?
        do {
            fetched = try await ListenerRatingsSync.fetchAggregates(store: store, movieIds: ["the-room-2003"])
            XCTFail("timeout must throw")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }
        XCTAssertEqual(ListenerRatingsSync.applying(fetched, to: cached), cached,
                       "a CloudKit timeout must not wipe the local snapshot")

        await store.fail(with: URLError(.notConnectedToInternet))
        fetched = nil
        do {
            fetched = try await ListenerRatingsSync.fetchAggregates(store: store, movieIds: ["the-room-2003"])
            XCTFail("offline must throw")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }
        XCTAssertEqual(ListenerRatingsSync.applying(fetched, to: cached), cached)

        await store.fail(with: nil)
        await store.seed(["r-new": ListenerRatingEntry(movieId: "the-room-2003", halfStars: 2)])
        let recovered = try await ListenerRatingsSync.fetchAggregates(store: store, movieIds: ["the-room-2003"])
        let applied = ListenerRatingsSync.applying(recovered, to: cached)
        XCTAssertNotEqual(applied, cached, "a successful refresh replaces the snapshot")
        let calls = await store.callCount()
        XCTAssertEqual(calls, 3)
    }
}
