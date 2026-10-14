import XCTest
@testable import MovieRouletteTuesday

final class CatalogTests: XCTestCase {
    /// Bundled catalog (`movies.json` in the app target).
    private var bundledMoviesURL: URL {
        if let url = Bundle.main.url(forResource: "movies", withExtension: "json") {
            return url
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // MovieRouletteTuesdayTests
            .deletingLastPathComponent() // project root
            .appendingPathComponent("MovieRouletteTuesday/Resources/movies.json")
    }

    private func loadBundledCatalog() async throws -> MovieCatalog {
        guard FileManager.default.fileExists(atPath: bundledMoviesURL.path) else {
            throw XCTSkip("movies.json not found at \(bundledMoviesURL.path)")
        }
        return try await FileCatalogSource(fileURL: bundledMoviesURL).loadCatalog()
    }

    func testDecodesMinimalJSONWithDefaults() async throws {
        let json = """
        {"categories":[{"id":"c","name":"C","colorHex":"#123456"}],
         "movies":[{"id":"m","title":"M","year":1999,"genre":"Drama"}]}
        """
        let catalog = try await DataCatalogSource(data: Data(json.utf8)).loadCatalog()
        XCTAssertEqual(catalog.schemaVersion, 1)
        XCTAssertEqual(catalog.categories[0].movieIds, [])
        XCTAssertNil(catalog.categories[0].weight)
        let movie = catalog.movies[0]
        XCTAssertEqual(movie.categories, [])
        XCTAssertEqual(movie.episodeIds, [])
        XCTAssertNil(movie.episodeTitle)
        XCTAssertFalse(movie.isInfamous)
    }

    func testRoundTripsThroughJSON() throws {
        let catalog = MovieCatalog(
            schemaVersion: 2,
            show: .mrt,
            categories: [RouletteCategory(id: "c", name: "C", fullName: "Category", colorHex: "#123456", weight: 2, movieIds: ["m"])],
            movies: [Movie(id: "m", title: "M", year: 1999, genre: "Drama", categories: ["c"],
                           episodeIds: ["Buzzsprout-1"], episodeTitle: "M",
                           posterURL: URL(string: "https://example.com/p.jpg"),
                           isInfamous: true, hostRating: 4.5)]
        )
        XCTAssertEqual(try MovieCatalog.decode(from: JSONEncoder().encode(catalog)), catalog)
        XCTAssertEqual(catalog.validationIssues(), [])
    }

    func testValidationFindsProblems() {
        let catalog = MovieCatalog(
            categories: [
                RouletteCategory(id: "c", name: "C", colorHex: "nope", movieIds: ["m", "ghost"]),
                RouletteCategory(id: "e", name: "E", colorHex: "#000000")
            ],
            movies: [Movie(id: "m", title: "M", year: 1999, genre: "Drama", categories: ["x"])]
        )
        let issues = catalog.validationIssues()
        XCTAssertTrue(issues.contains { $0.contains("invalid colorHex") })
        XCTAssertTrue(issues.contains { $0.contains("unknown movie 'ghost'") })
        XCTAssertTrue(issues.contains { $0.contains("unknown category 'x'") })
        XCTAssertTrue(issues.contains { $0.contains("'e' has no movies") })
        XCTAssertTrue(issues.contains { $0.contains("doesn't list that category") })
    }

    func testMissingBundleResourceThrows() async {
        let source = BundleCatalogSource(resourceName: "definitely-not-here", bundle: .main)
        do {
            _ = try await source.loadCatalog()
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? CatalogLoadingError, .resourceNotFound("definitely-not-here.json"))
        }
    }

    func testFallbackSourceUsesFallbackOnFailure() async throws {
        let good = DataCatalogSource(data: Data(#"{"categories":[],"movies":[]}"#.utf8))
        let bad = DataCatalogSource(data: Data("not json".utf8))
        let catalog = try await FallbackCatalogSource(primary: bad, fallback: good).loadCatalog()
        XCTAssertEqual(catalog.movies.count, 0)
    }

    func testBundledCatalogIsConsistentAndReal() async throws {
        let catalog = try await loadBundledCatalog()
        XCTAssertEqual(catalog.validationIssues(), [])
        XCTAssertEqual(catalog.categories.count, 10)
        XCTAssertEqual(catalog.schemaVersion, 2)
        XCTAssertGreaterThanOrEqual(catalog.movies.count, 170)
        XCTAssertLessThanOrEqual(catalog.movies.count, 190)
        let selector = MovieSelector()
        for category in catalog.categories {
            XCTAssertGreaterThanOrEqual(
                selector.candidates(for: category, in: catalog).count, 4,
                category.displayName
            )
            XCTAssertNotNil(HexColor(category.colorHex), category.id)
        }
        // Real Buzzsprout guids only — no sample placeholders.
        for movie in catalog.movies {
            XCTAssertFalse(movie.episodeIds.isEmpty, movie.title)
            XCTAssertTrue(
                movie.episodeIds.allSatisfy { $0.hasPrefix("Buzzsprout-") },
                "\(movie.title): \(movie.episodeIds)"
            )
            XCTAssertTrue((1920...2030).contains(movie.year), "\(movie.title) \(movie.year)")
        }
        XCTAssertEqual(catalog.showInfo.applePodcastID, "1666123849")
        XCTAssertNotNil(catalog.showInfo.rssURL)
    }

    func testBundledCatalogSpotChecks() async throws {
        let catalog = try await loadBundledCatalog()
        let byTitle = Dictionary(uniqueKeysWithValues: catalog.movies.map { ($0.title, $0) })
        XCTAssertNil(byTitle["Die Hard"], "Sample catalog titles must not remain")
        XCTAssertEqual(byTitle["The Outsiders"]?.year, 1983)
        XCTAssertEqual(byTitle["Crash"]?.year, 1996) // Cronenberg, per research
        XCTAssertTrue(byTitle["The Ugly Stepsister"]?.episodeIds.contains("Buzzsprout-19877460") == true)
        XCTAssertTrue(catalog.categories.contains { $0.id == "cat-horror" && $0.name == "Horror" })
        XCTAssertTrue(catalog.categories.contains { $0.id == "cat-listener" && $0.movieIds.count >= 4 })
    }

    func testEpisodeLabelUsesRealTitles() {
        let movie = Movie(
            id: "x", title: "The Outsiders", year: 1983, genre: "Drama",
            episodeIds: ["Buzzsprout-19913482"], episodeTitle: "The Outsiders"
        )
        XCTAssertEqual(
            EpisodeLabel.discussedText(for: movie),
            "Discussed on The Outsiders"
        )
        let ep = PodcastEpisode(guid: "Buzzsprout-19913482", title: "The Outsiders", season: 4, episode: 34)
        XCTAssertEqual(
            EpisodeLabel.discussedText(for: movie, episodesByGUID: [ep.guid: ep]),
            "Discussed on The Outsiders (S4E34)"
        )
    }

    func testPodcastDeepLinks() {
        XCTAssertNotNil(PodcastLinks.appleShow())
        XCTAssertNotNil(PodcastLinks.spotifyShow())
        XCTAssertNotNil(PodcastLinks.appleSearch(episodeTitle: "The Outsiders"))
        XCTAssertNotNil(PodcastLinks.spotifySearch(episodeTitle: "The Outsiders"))
        XCTAssertEqual(
            PodcastLinks.buzzsproutEpisode(guid: "Buzzsprout-19913482")?.absoluteString,
            "https://www.buzzsprout.com/2117292/episodes/19913482"
        )
    }

    func testStatsCalculator() {
        let catalog = MovieCatalog(
            categories: [
                RouletteCategory(id: "a", name: "A", colorHex: "#111111", movieIds: ["m1"]),
                RouletteCategory(id: "b", name: "B", colorHex: "#222222", movieIds: ["m2"]),
            ],
            movies: [
                Movie(id: "m1", title: "One", year: 2000, genre: "Horror", categories: ["a"]),
                Movie(id: "m2", title: "Two", year: 2001, genre: "Comedy", categories: ["b"]),
            ]
        )
        let history = [
            SpinResult(movieId: "m1", categoryId: "a"),
            SpinResult(movieId: "m1", categoryId: "a"),
            SpinResult(movieId: "m2", categoryId: "b"),
        ]
        let snap = StatsCalculator.snapshot(history: history, catalog: catalog)
        XCTAssertEqual(snap.totalSpins, 3)
        XCTAssertEqual(snap.distinctMovies, 2)
        XCTAssertEqual(snap.mostSpunMovie?.id, "m1")
        XCTAssertEqual(snap.mostSpunMovie?.count, 2)
        XCTAssertEqual(snap.mostSpunCategory?.id, "a")
        XCTAssertEqual(snap.genreBreakdown.first?.genre, "Horror")
    }

    func testEveryBundledCategoryHasAThemeColor() async throws {
        let catalog = try await loadBundledCatalog()
        for category in catalog.categories {
            XCTAssertNotNil(CategoryPalette.known[category.id], "no theme color for \(category.id)")
            XCTAssertEqual(category.displayHex, CategoryPalette.known[category.id])
        }
    }

    // TestFlight 1.0 (4): the line under the title used `genre`, the Categories section used categories.
    func testSubtitleUsesSameCategoryNamesAsCategoriesSection() {
        let catalog = MovieCatalog(
            categories: [
                RouletteCategory(id: "a", name: "Cult", fullName: "Cult & Bizarre", colorHex: "#111111", movieIds: ["m1"]),
                RouletteCategory(id: "b", name: "Horror", colorHex: "#222222", movieIds: ["m1"]),
            ],
            movies: [Movie(id: "m1", title: "One", year: 2000, genre: "Drama", categories: ["a", "b"])]
        )
        let movie = catalog.movies[0]
        XCTAssertEqual(catalog.subtitle(for: movie), "2000 · Cult & Bizarre, Horror")
        let section = movie.categories.compactMap { catalog.category(withId: $0)?.displayName }
        for name in section { XCTAssertTrue(catalog.subtitle(for: movie).contains(name)) }
    }

    // TestFlight 1.0 (4): Episodes vs Movies totals differ because the feed has non-movie episodes.
    func testEpisodeTotalsSeparateFeedFromCatalog() {
        let catalog = MovieCatalog(
            categories: [RouletteCategory(id: "a", name: "A", colorHex: "#111111", movieIds: ["m1", "m2"])],
            movies: [
                Movie(id: "m1", title: "One", year: 2000, genre: "Drama", categories: ["a"], episodeIds: ["e1"]),
                Movie(id: "m2", title: "Two", year: 2001, genre: "Drama", categories: ["a"], episodeIds: ["e2"]),
            ]
        )
        let feed = [PodcastEpisode(guid: "e1", title: "1"), PodcastEpisode(guid: "e2", title: "2"),
                    PodcastEpisode(guid: "trailer", title: "Trailer")]
        let totals = EpisodeTotals(episodes: feed, catalog: catalog)
        XCTAssertEqual(totals.feedEpisodes, 3)
        XCTAssertEqual(totals.feedEpisodesWithFilm, 2)
        XCTAssertEqual(EpisodeTotals.catalogEpisodeCount(catalog), 2)
    }

    // TestFlight 1.0 (4): every movie page reads Times Spun from the one shared store, live.
    @MainActor
    func testSpinCountComesFromSharedStoreAndUpdatesLive() {
        let store = SpinHistoryStore(fileStore: nil)
        XCTAssertEqual(store.stats.spinCount(forMovie: "m1"), 0)
        store.record(SpinResult(movieId: "m1", categoryId: "a"))
        XCTAssertEqual(store.stats.spinCount(forMovie: "m1"), 1)
        store.record(SpinResult(movieId: "m1", categoryId: "a"))
        XCTAssertEqual(store.stats.spinCount(forMovie: "m1"), 2)
    }
}


/// tmdbId + streaming providers: optional, backward compatible, no UI.
final class CatalogStreamingFieldTests: XCTestCase {
    private let base = #""id":"the-thing-1982","title":"The Thing","year":1982,"genre":"Horror""#

    func testDecodesWithoutNewFields() throws {
        let m = try JSONDecoder().decode(Movie.self, from: Data("{\(base)}".utf8))
        XCTAssertNil(m.tmdbId)
        XCTAssertNil(m.streaming)
    }

    func testDecodesWithNewFields() throws {
        let json = """
        {\(base),"tmdbId":1091,"streaming":{"region":"US","updated":"2026-10-14",
         "link":"https://www.themoviedb.org/movie/1091-the-thing/watch?locale=US",
         "stream":[{"id":8,"name":"Netflix","logo":"/pbpMk2JmcoNnQwx5JGpXngfoWtp.jpg","priority":1}],
         "free":[],
         "rent":[{"id":2,"name":"Apple TV","logo":"/peURlLlr8jggOwK53fJ5wdQl05y.jpg","priority":4}],
         "buy":[{"id":3,"name":"Google Play Movies","logo":null}]}}
        """
        let m = try JSONDecoder().decode(Movie.self, from: Data(json.utf8))
        XCTAssertEqual(m.tmdbId, 1091)
        let s = try XCTUnwrap(m.streaming)
        XCTAssertEqual(s.region, "US")
        XCTAssertEqual(s.updated, "2026-10-14")
        XCTAssertEqual(s.link, "https://www.themoviedb.org/movie/1091-the-thing/watch?locale=US")
        XCTAssertEqual(s.stream, [StreamingInfo.Provider(id: 8, name: "Netflix", logo: "/pbpMk2JmcoNnQwx5JGpXngfoWtp.jpg", priority: 1)])
        XCTAssertEqual(s.stream[0].logoURL?.absoluteString, "https://image.tmdb.org/t/p/w92/pbpMk2JmcoNnQwx5JGpXngfoWtp.jpg")
        XCTAssertTrue(s.free.isEmpty)
        XCTAssertEqual(s.rent.first?.priority, 4)
        XCTAssertNil(s.buy.first?.logo)
        XCTAssertNil(s.buy.first?.priority)
        XCTAssertNil(s.buy.first?.logoURL)
        XCTAssertFalse(s.isEmpty)
        let again = try JSONDecoder().decode(Movie.self, from: JSONEncoder().encode(m))
        XCTAssertEqual(again, m, "round trip")
    }

    func testEmptyStreamingLists() throws {
        let json = #"{\#(base),"streaming":{"region":"US","updated":"2026-10-14","link":"x","stream":[],"free":[],"rent":[],"buy":[]}}"#
        let m = try JSONDecoder().decode(Movie.self, from: Data(json.utf8))
        XCTAssertNil(m.tmdbId)
        XCTAssertEqual(m.streaming?.isEmpty, true)
    }

    func testMalformedNewFieldsNeverBreakTheCatalog() throws {
        let m = try JSONDecoder().decode(Movie.self, from: Data(#"{\#(base),"tmdbId":"abc","streaming":[1,2]}"#.utf8))
        XCTAssertNil(m.tmdbId)
        XCTAssertNil(m.streaming)
    }

    func testBundledCatalogStillDecodes() async throws {
        let url = Bundle.main.url(forResource: "movies", withExtension: "json")
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("MovieRouletteTuesday/Resources/movies.json")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("no movies.json") }
        let catalog = try await FileCatalogSource(fileURL: url).loadCatalog()
        XCTAssertFalse(catalog.movies.isEmpty)
        XCTAssertTrue(catalog.movies.allSatisfy { $0.tmdbId == nil && $0.streaming == nil }, "current movies.json has neither")
    }
}
