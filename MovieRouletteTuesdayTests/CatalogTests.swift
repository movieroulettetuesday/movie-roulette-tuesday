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
    }

    func testRoundTripsThroughJSON() throws {
        let catalog = MovieCatalog(
            schemaVersion: 2,
            show: .mrt,
            categories: [RouletteCategory(id: "c", name: "C", fullName: "Category", colorHex: "#123456", weight: 2, movieIds: ["m"])],
            movies: [Movie(id: "m", title: "M", year: 1999, genre: "Drama", categories: ["c"],
                           episodeIds: ["Buzzsprout-1"], episodeTitle: "M",
                           posterURL: URL(string: "https://example.com/p.jpg"),
                           hostRating: 4.5)]
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

    /// 1.0.1: ties sort by count descending, then id / genre ascending, so the
    /// "Most spun" cards and equal bars never change between launches.
    func testStatsTiesAreDeterministic() {
        let catalog = MovieCatalog(
            categories: ["c", "a", "b"].map { RouletteCategory(id: $0, name: $0.uppercased(), colorHex: "#111111") },
            movies: [
                Movie(id: "m2", title: "Two", year: 2001, genre: "Horror", categories: ["b"]),
                Movie(id: "m1", title: "One", year: 2000, genre: "Comedy", categories: ["a"]),
                Movie(id: "m3", title: "Three", year: 2002, genre: "Drama", categories: ["c"]),
                Movie(id: "m0", title: "Zero", year: 1999, genre: "Action", categories: ["c"]),
            ]
        )
        // m2, m1, m3: 2 each (tie); m0: 1. Categories b 2, a 2, c 3. Genres Horror 2, Comedy 2, Drama 2, Action 1.
        let history = ["m2:b", "m3:c", "m1:a", "m2:b", "m3:c", "m1:a", "m0:c"].map {
            let p = $0.split(separator: ":").map(String.init)
            return SpinResult(movieId: p[0], categoryId: p[1])
        }
        // An archived tie on top of the detailed history: still deterministic.
        let archive = SpinHistoryArchive(totalSpins: 2, movieCounts: ["m0": 1, "zz": 1], categoryCounts: ["a": 1, "b": 1])
        for _ in 0..<20 {
            let snap = StatsCalculator.snapshot(history: history, catalog: catalog)
            XCTAssertEqual(snap.mostSpunMovie, CountedID(id: "m1", count: 2))
            XCTAssertEqual(snap.mostSpunCategory, CountedID(id: "c", count: 3))
            XCTAssertEqual(snap.categoryBreakdown, [CountedID(id: "c", count: 3), CountedID(id: "a", count: 2), CountedID(id: "b", count: 2)])
            XCTAssertEqual(snap.genreBreakdown, [CountedGenre(genre: "Comedy", count: 2), CountedGenre(genre: "Drama", count: 2),
                                                 CountedGenre(genre: "Horror", count: 2), CountedGenre(genre: "Action", count: 1)])
            let withArchive = StatsCalculator.snapshot(history: history, catalog: catalog, archive: archive)
            XCTAssertEqual(withArchive.mostSpunMovie, CountedID(id: "m0", count: 2))
            XCTAssertEqual(withArchive.categoryBreakdown.map(\.id), ["a", "b", "c"])
        }
        // Plain code-point order: uppercase before lowercase, shorter prefix first.
        XCTAssertEqual(StatsCalculator.ranked(["b": 1, "B": 1, "a": 2, "ab": 1]).map(\.key), ["a", "B", "ab", "b"])
        XCTAssertNil(StatsCalculator.snapshot(history: [], catalog: catalog).mostSpunMovie)
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
        XCTAssertGreaterThan(catalog.movies.filter { $0.tmdbId != nil && $0.streaming != nil }.count, 150, "bundled catalog carries streaming data")
        let byId = Dictionary(uniqueKeysWithValues: catalog.movies.map { ($0.id, $0) })
        // Approved Oct 14 year fixes (ids unchanged so history/ratings keep working).
        XCTAssertEqual(byId["war-of-the-roses-1980"]?.year, 1989)
        XCTAssertEqual(byId["brewsters-millions-1980"]?.year, 1985)
        XCTAssertEqual(byId["ed-wood-1950"]?.year, 1994)
    }
}


final class StreamingFilterSortTests: XCTestCase {
    private typealias P = StreamingInfo.Provider
    private let netflix = P(id: 8, name: "Netflix", logo: "/n.jpg", priority: 1)
    private let max = P(id: 1899, name: "Max", logo: "/m.jpg", priority: 2)
    private let tubi = P(id: 73, name: "Tubi TV", logo: nil, priority: 5)
    private let apple = P(id: 2, name: "Apple TV", logo: "/a.jpg", priority: 3)

    private func movie(_ id: String, stream: [P] = [], free: [P] = [], rent: [P] = [], buy: [P] = [], data: Bool = true) -> Movie {
        Movie(id: id, title: id, year: 2000, genre: "Drama",
              streaming: data ? StreamingInfo(updated: "2026-10-13", link: "https://x", stream: stream, free: free, rent: rent, buy: buy) : nil)
    }

    private var movies: [Movie] {
        [
            movie("a-rent", rent: [apple], buy: [apple]),
            movie("b-netflix", stream: [netflix]),
            movie("c-none", data: false),
            movie("d-max-tubi", stream: [max], free: [tubi]),
            movie("e-tubi", free: [tubi]),
            movie("f-empty"),
        ]
    }

    func testMyServicesSerialization() {
        var s = MyServices(serialized: "8, 1899,x,,8")
        XCTAssertEqual(s.ids, [8, 1899])
        s.toggle(8); s.toggle(73)
        XCTAssertEqual(s.serialized, "73,1899")
        XCTAssertTrue(MyServices(serialized: "").isEmpty)
    }

    func testServicesFromCatalog() {
        let list = StreamingCatalog.services(in: movies)
        XCTAssertEqual(list.map(\.name), ["Tubi TV", "Max", "Netflix"], "most titles first, then by name; rent/buy stores excluded")
    }

    func testOnMyServicesFilter() {
        XCTAssertEqual(StreamingCatalog.filter(movies, services: MyServices(ids: [8])).map(\.id), ["b-netflix"])
        XCTAssertEqual(StreamingCatalog.filter(movies, services: MyServices(ids: [73])).map(\.id), ["d-max-tubi", "e-tubi"], "free counts")
        XCTAssertEqual(StreamingCatalog.filter(movies, services: MyServices(ids: [2])).map(\.id), [], "rent/buy is not 'on my services'")
        XCTAssertTrue(StreamingCatalog.filter(movies, services: MyServices()).isEmpty)
        XCTAssertEqual(StreamingCatalog.matchingServices(movies[3], services: MyServices(ids: [73, 1899])).map(\.id), [1899, 73])
    }

    func testAvailableFirstWithServices() {
        let sorted = StreamingCatalog.availableFirst(movies, services: MyServices(ids: [8]))
        XCTAssertEqual(sorted.map(\.id), ["b-netflix", "d-max-tubi", "e-tubi", "a-rent", "c-none", "f-empty"])
    }

    func testAvailableFirstWithoutServicesUsesAnyStreaming() {
        let sorted = StreamingCatalog.availableFirst(movies, services: MyServices())
        XCTAssertEqual(sorted.map(\.id), ["b-netflix", "d-max-tubi", "e-tubi", "a-rent", "c-none", "f-empty"])
        XCTAssertEqual(StreamingCatalog.availableFirst([], services: MyServices()), [])
    }

    func testRentOrBuyAndLabels() {
        let info = StreamingInfo(updated: "2026-10-13", rent: [apple, netflix], buy: [apple, max])
        XCTAssertEqual(StreamingCatalog.rentOrBuy(info).map(\.id), [2, 8, 1899])
        XCTAssertEqual(StreamingCatalog.updatedLabel("2026-10-13"), "Oct 13")
        XCTAssertNil(StreamingCatalog.updatedLabel("soon"))
        XCTAssertNil(StreamingCatalog.updatedLabel(nil))
        XCTAssertEqual(StreamingCatalog.tmdbNotice, "This product uses the TMDB API but is not endorsed or certified by TMDB.")
    }
}

final class WhereToWatchDisplayTests: XCTestCase {
    private let netflix = StreamingInfo.Provider(id: 8, name: "Netflix", logo: "/n.jpg", priority: 1)

    func testProvidersShownWithLinkAndAttribution() {
        let m = Movie(id: "a", title: "A", year: 2000, genre: "G", tmdbId: 1,
                      streaming: StreamingInfo(updated: "2026-10-13", link: "https://www.themoviedb.org/movie/1/watch?locale=US", stream: [netflix]))
        let d = WhereToWatchDisplay(movie: m)
        XCTAssertTrue(d.showsProviders)
        XCTAssertFalse(d.showsEmptyMessage)
        XCTAssertEqual(d.link?.absoluteString, "https://www.themoviedb.org/movie/1/watch?locale=US")
        XCTAssertTrue(d.footer?.hasPrefix(StreamingCatalog.attribution) == true)
        XCTAssertTrue(d.footer?.contains("updated") == true)
    }

    func testAllListsEmptyShowsMessageKeepsLinkAndFooter() {
        let m = Movie(id: "b", title: "B", year: 2000, genre: "G", tmdbId: 2,
                      streaming: StreamingInfo(updated: "2026-10-13", link: "https://www.themoviedb.org/movie/2/watch?locale=US"))
        let d = WhereToWatchDisplay(movie: m)
        XCTAssertTrue(d.showsEmptyMessage)
        XCTAssertEqual(d.region, "US")
        XCTAssertNotNil(d.link)
        XCTAssertTrue(d.footer?.contains("updated") == true)
    }

    func testTmdbIdWithoutStreamingDataStillLinks() {
        let d = WhereToWatchDisplay(movie: Movie(id: "c", title: "C", year: 2000, genre: "G", tmdbId: 3))
        XCTAssertTrue(d.showsEmptyMessage)
        XCTAssertEqual(d.link?.absoluteString, "https://www.themoviedb.org/movie/3/watch?locale=US")
        XCTAssertEqual(d.footer, StreamingCatalog.attribution)
    }

    func testNoTmdbIdShowsOnlyMessage() {
        let d = WhereToWatchDisplay(movie: Movie(id: "d", title: "Scarlet Warning 666", year: 2000, genre: "G"))
        XCTAssertTrue(d.showsEmptyMessage)
        XCTAssertEqual(d.region, "US")
        XCTAssertNil(d.link)
        XCTAssertNil(d.footer)
        XCTAssertEqual(WhereToWatchDisplay.emptyMessage, "No streaming sources found.")
    }
}
