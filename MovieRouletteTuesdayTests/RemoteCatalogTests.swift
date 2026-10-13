import XCTest
@testable import MovieRouletteTuesday
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Remote movie list: GitHub copy validated, cached, and falling back cleanly.
final class RemoteCatalogTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("mrt-remote-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: Fixtures

    private var bundledURL: URL {
        if let url = Bundle.main.url(forResource: "movies", withExtension: "json") { return url }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MovieRouletteTuesday/Resources/movies.json")
    }

    private func bundled() throws -> MovieCatalog {
        guard FileManager.default.fileExists(atPath: bundledURL.path) else { throw XCTSkip("no movies.json") }
        return try MovieCatalog.decode(from: Data(contentsOf: bundledURL))
    }

    private static let newGuid = "Buzzsprout-99999999"

    /// The bundled list plus one new episode's movie, added the CATALOG.md way.
    private func remoteWithNewMovie() throws -> MovieCatalog {
        var catalog = try bundled()
        let movie = Movie(id: "test-new-movie-2026", title: "Test New Movie", year: 2026, genre: "Horror",
                          categories: ["cat-horror"], episodeIds: [Self.newGuid], episodeTitle: "Test New Movie")
        catalog.movies.append(movie)
        let i = try XCTUnwrap(catalog.categories.firstIndex { $0.id == "cat-horror" })
        catalog.categories[i].movieIds.append(movie.id)
        return catalog
    }

    private func cache(build: String = "7") -> CatalogCache {
        CatalogCache(fileURL: dir.appendingPathComponent(CatalogCache.fileName), build: build)
    }

    private func remote(status: Int = 200, body: Data) -> RemoteCatalogSource {
        RemoteCatalogSource(url: RemoteCatalog.url) { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertNil(request.httpBody)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (body, response)
        }
    }

    private func offline() -> RemoteCatalogSource {
        RemoteCatalogSource(url: RemoteCatalog.url) { _ in throw URLError(.notConnectedToInternet) }
    }

    private var bundledSource: FileCatalogSource { FileCatalogSource(fileURL: bundledURL) }

    // MARK: Tests

    func testRawURLPointsAtRepoMoviesJSON() {
        XCTAssertEqual(RemoteCatalog.url.absoluteString,
            "https://raw.githubusercontent.com/movieroulettetuesday/movie-roulette-tuesday/main/MovieRouletteTuesday/Resources/movies.json")
        XCTAssertLessThanOrEqual(RemoteCatalog.timeout, 10)
    }

    func testBundledCatalogPassesValidation() throws {
        let catalog = try bundled()
        XCTAssertNoThrow(try CatalogValidator.validate(catalog))
    }

    func testRemoteSuccessReplacesAndCaches() async throws {
        let fresh = try remoteWithNewMovie()
        let cache = cache()
        let refresher = CatalogRefresher(remote: remote(body: try JSONEncoder().encode(fresh)), cache: cache)

        let got = try await refresher.refresh(now: Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(got, fresh)
        XCTAssertEqual(cache.fetchedAt, Date(timeIntervalSince1970: 1_000))
        // Next launch (no network) shows the cached remote list, not the bundle.
        let local = try await LocalCatalog.source(cache: cache, bundled: bundledSource).loadCatalog()
        XCTAssertNotNil(local.movie(withId: "test-new-movie-2026"))
        XCTAssertNotNil(LocalCatalog.loadSync(cache: cache, bundle: Bundle(for: Self.self))?.movie(withId: "test-new-movie-2026"))
    }

    func testBadRemoteNeverReplacesCache() async throws {
        let good = try remoteWithNewMovie()
        let cache = cache()
        try cache.save(JSONEncoder().encode(good))

        var futureSchema = good; futureSchema.schemaVersion = 99
        var empty = good; empty.movies = []; empty.categories = []
        var broken = good; broken.movies.removeLast() // cat-horror now names an unknown movie
        let bodies: [(String, Int, Data)] = [
            ("not json", 200, Data("<html>rate limited</html>".utf8)),
            ("truncated", 200, try JSONEncoder().encode(good).prefix(500)),
            ("future schema", 200, try JSONEncoder().encode(futureSchema)),
            ("empty", 200, try JSONEncoder().encode(empty)),
            ("inconsistent", 200, try JSONEncoder().encode(broken)),
            ("http 404", 404, try JSONEncoder().encode(good)),
        ]
        for (label, status, body) in bodies {
            do {
                _ = try await CatalogRefresher(remote: remote(status: status, body: body), cache: cache).refresh()
                XCTFail("\(label): should be rejected")
            } catch {}
            XCTAssertEqual(cache.loadCatalog(), good, "\(label): cache must be untouched")
        }
        // Without any cache a bad remote leaves the app on the bundled list.
        let empty2 = CatalogCache(fileURL: dir.appendingPathComponent("none.json"), build: "7")
        _ = try? await CatalogRefresher(remote: remote(body: Data("nope".utf8)), cache: empty2).refresh()
        let local = try await LocalCatalog.source(cache: empty2, bundled: bundledSource).loadCatalog()
        XCTAssertEqual(local, try bundled())
    }

    func testOfflineUsesCacheThenBundle() async throws {
        let cached = try remoteWithNewMovie()
        let cache = cache()
        try cache.save(JSONEncoder().encode(cached))

        do {
            _ = try await CatalogRefresher(remote: offline(), cache: cache).refresh()
            XCTFail("offline should throw")
        } catch {}
        // 1) Offline with a cache: cached remote copy.
        var local = try await LocalCatalog.source(cache: cache, bundled: bundledSource).loadCatalog()
        XCTAssertEqual(local, cached)
        // 2) Cache from another app build (after an update): ignored, bundle wins.
        local = try await LocalCatalog.source(cache: self.cache(build: "8"), bundled: bundledSource).loadCatalog()
        XCTAssertEqual(local, try bundled())
        // 3) Corrupt cache: bundle.
        try Data("garbage".utf8).write(to: cache.fileURL)
        local = try await LocalCatalog.source(cache: cache, bundled: bundledSource).loadCatalog()
        XCTAssertEqual(local, try bundled())
        // 4) No cache at all: bundle.
        cache.clear()
        local = try await LocalCatalog.source(cache: cache, bundled: bundledSource).loadCatalog()
        XCTAssertEqual(local, try bundled())
        local = try await LocalCatalog.source(cache: nil, bundled: bundledSource).loadCatalog()
        XCTAssertEqual(local, try bundled())
    }

    func testMovieIdsStayStableAcrossRemoteUpdate() throws {
        let old = try bundled().deduplicated()
        let new = try remoteWithNewMovie().deduplicated()
        // Spin history and ratings are keyed by movie id: every old id still resolves to the same film.
        for movie in old.movies {
            let same = try XCTUnwrap(new.movie(withId: movie.id), movie.id)
            XCTAssertEqual(same, movie)
        }
        let history = old.movies.prefix(5).map { SpinResult(movieId: $0.id, categoryId: $0.categories.first ?? "") }
        XCTAssertTrue(history.allSatisfy { new.movie(withId: $0.movieId) != nil })
        // Ids are unique, so dictionaries keyed by id never trap.
        XCTAssertEqual(Set(new.movies.map(\.id)).count, new.movies.count)
    }

    func testNewEpisodeFindsItsMovieOnlyInRefreshedCatalog() throws {
        let old = try bundled(), new = try remoteWithNewMovie()
        XCTAssertNil(old.movie(forEpisodeGuid: Self.newGuid))
        let movie = try XCTUnwrap(new.movie(forEpisodeGuid: Self.newGuid))
        XCTAssertEqual(movie.id, "test-new-movie-2026")
        XCTAssertEqual(EpisodeLabel.discussedText(for: movie).isEmpty, false)
    }

    func testCatalogJSONIgnoresUnknownKeysLikeNote() throws {
        let json = ##"{"_note":"x","schemaVersion":2,"categories":[{"id":"c","name":"C","colorHex":"#123456","movieIds":["m"]}],"movies":[{"id":"m","title":"M","year":1999,"genre":"Drama","categories":["c"],"futureField":1}]}"##
        XCTAssertNoThrow(try CatalogValidator.decodeValidated(Data(json.utf8)))
    }
}
