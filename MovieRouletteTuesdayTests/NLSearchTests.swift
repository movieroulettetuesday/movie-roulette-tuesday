import XCTest
@testable import MovieRouletteTuesday

/// Deterministic NL search rules beyond the shared cases: AND with title,
/// providers, ratings, watched status, toolbar AND, validation, chips, and
/// question detection. No model.
final class NLSearchTests: XCTestCase {
    private var catalog: MovieCatalog!
    private var episodes: [PodcastEpisode]!
    private var ratings: PersonalRatings!

    override func setUp() {
        super.setUp()
        catalog = NLSearchFixture.catalog()
        episodes = NLSearchFixture.episodes()
        ratings = NLSearchFixture.ratings()
    }

    private func movieIDs(_ filter: NLSearchFilter, in movies: [Movie]? = nil) -> [String] {
        let f = NLSearch.validated(filter, catalog: catalog)
        return NLSearch.apply(f, toMovies: movies ?? catalog.movies, catalog: catalog, ratings: ratings,
                              services: NLSearchFixture.services).movies.map(\.id)
    }

    private func episodeIDs(_ filter: NLSearchFilter) -> [String] {
        let f = NLSearch.validated(filter, catalog: catalog)
        return NLSearch.apply(f, toEpisodes: episodes, catalog: catalog, ratings: ratings,
                              services: NLSearchFixture.services, calendar: NLSearchFixture.utc).map(\.guid)
    }

    func testTitleAndGenreAndYearAND() {
        // CatalogSearch alone can't AND a title with a genre and a range.
        XCTAssertEqual(movieIDs(.init(title: "The Thing", yearMin: 2000, genre: "Horror")), ["the-thing-2011"])
        XCTAssertEqual(movieIDs(.init(title: "The Thing", genre: "Sci-Fi")), [])
    }

    func testShudderMatchesOfficialAndChannelNamesButVuduAndRentDoNot() {
        XCTAssertEqual(movieIDs(.init(provider: "Shudder")), ["the-devils-rain-1975", "the-thing-1982"])
        XCTAssertEqual(movieIDs(.init(provider: "Netflix")), ["blade-runner-1982", "eternal-sunshine-2004", "the-thing-2011"])
        // Vudu is rent-only: validation nulls it, and even unvalidated it matches nothing.
        XCTAssertNil(NLSearch.validated(.init(provider: "Vudu"), catalog: catalog).provider)
        XCTAssertEqual(NLSearch.apply(.init(provider: "Vudu"), toMovies: catalog.movies, catalog: catalog,
                                      ratings: ratings, services: NLSearchFixture.services).movies, [])
    }

    func testFreeOnlyWithProviderNeedsTheFreeList() {
        XCTAssertEqual(movieIDs(.init(provider: "Shudder", freeOnly: true)), [], "Shudder is stream-only here")
        XCTAssertEqual(movieIDs(.init(provider: "Pluto", freeOnly: true)), ["the-devils-rain-1975", "the-evil-dead-1981"])
    }

    func testRatingsMinMaxUnratedAndRated() {
        XCTAssertEqual(movieIDs(.init(ratingMin: 4)), ["alien-1979", "blade-runner-1982", "the-godfather-1972", "the-thing-1982"])
        XCTAssertEqual(movieIDs(.init(ratingMax: 2)), ["pulp-fiction-1994", "the-room-2003"])
        XCTAssertEqual(movieIDs(.init(ratingMax: 1)), ["the-room-2003"])
        XCTAssertEqual(movieIDs(.init(genre: "Horror", unrated: true)), ["hellraiser-1987", "the-evil-dead-1981", "the-shining-1980", "the-thing-2011"])
        XCTAssertEqual(movieIDs(.init(genre: "Horror", unrated: false)), ["the-devils-rain-1975", "the-thing-1982"])
        // unrated: true wins over a min.
        XCTAssertEqual(movieIDs(.init(genre: "Horror", ratingMin: 4, unrated: true)),
                       movieIDs(.init(genre: "Horror", unrated: true)))
    }

    func testWatchedUnwatchedAndWatchlist() {
        XCTAssertEqual(movieIDs(.init(genre: "Horror", watched: .watched)), ["the-evil-dead-1981", "the-thing-1982"])
        XCTAssertEqual(movieIDs(.init(genre: "Horror", watched: .unwatched)),
                       ["hellraiser-1987", "the-devils-rain-1975", "the-shining-1980", "the-thing-2011"])
        XCTAssertEqual(movieIDs(.init(watched: .watchlist)), ["blade-runner-1982", "the-devils-rain-1975", "titanic-1997"])
        XCTAssertEqual(movieIDs(.init(genre: "Horror", watched: .any)), movieIDs(.init(genre: "Horror")))
    }

    func testFiltersOnlyReturnMatchesWithoutCatalogSearch() {
        let f = NLSearch.validated(.init(genre: "Horror", freeOnly: true), catalog: catalog)
        XCTAssertFalse(f.hasSearchText)
        XCTAssertNil(f.searchText, "never an empty CatalogSearch query")
        XCTAssertEqual(CatalogSearch.movies(catalog.movies, matching: "", catalog: catalog), [], "why: empty query has no hits")
        XCTAssertFalse(movieIDs(f).isEmpty)
    }

    func testEmptyFilterMeansKeywordSearch() {
        XCTAssertTrue(NLSearchFilter().isEmpty)
        XCTAssertTrue(NLSearchFilter(kind: .any, watched: .any).isEmpty)
        XCTAssertTrue(NLSearch.validated(.init(title: "  ?? ", freeOnly: false, onMyServices: false), catalog: catalog).isEmpty)
        XCTAssertFalse(NLSearchFilter(kind: .movie).isEmpty)
    }

    func testToolbarFiltersANDWithChips() {
        // The Movies toolbar already narrowed to the Cult category.
        let cult = catalog.movies.filter { $0.categories.contains("cat-cult") }
        XCTAssertEqual(movieIDs(.init(genre: "Horror"), in: cult), ["the-devils-rain-1975", "the-thing-1982"])
        XCTAssertEqual(movieIDs(.init(freeOnly: true), in: cult), ["the-devils-rain-1975", "the-room-2003", "the-thing-1982"])
    }

    func testOnMyServicesUsesServiceMembership() {
        XCTAssertEqual(movieIDs(.init(onMyServices: true)),
                       ["alien-1979", "heathers-1989", "pulp-fiction-1994", "the-thing-1982"])
        XCTAssertEqual(NLSearch.apply(.init(onMyServices: true), toMovies: catalog.movies, catalog: catalog,
                                      ratings: ratings, services: MyServices()).movies, [], "no services chosen")
    }

    func testHostsAndShowNotesAreNotSearched() {
        XCTAssertEqual(episodeIDs(.init(title: "karl")), [])
        XCTAssertEqual(episodeIDs(.init(title: "rachael")), [])
        XCTAssertEqual(movieIDs(.init(title: "karl")), [])
    }

    func testEpisodesUseLinkedMovieYearElsePubYear() {
        // ep-bonus has no movie (pub 2025); ep-thing's movie is 1982 even though it aired in 2025.
        XCTAssertEqual(episodeIDs(.init(yearMin: 2025, yearMax: 2025)), ["ep-bonus"])
        XCTAssertEqual(episodeIDs(.init(yearMin: 1982, yearMax: 1982)), ["ep-thing"])
    }

    func testEpisodeWithoutMovieFailsMovieLevelConstraints() {
        XCTAssertFalse(episodeIDs(.init(watched: .unwatched)).contains("ep-bonus"))
        XCTAssertFalse(episodeIDs(.init(unrated: true)).contains("ep-bonus"))
        XCTAssertTrue(episodeIDs(.init(title: "mailbag")).contains("ep-bonus"))
    }

    func testEpisodeSeasonEpisodeAndTitleUseCatalogSearchOrder() {
        XCTAssertEqual(episodeIDs(.init(season: 4, episode: 39)), ["ep-s4e39"])
        XCTAssertEqual(episodeIDs(.init(season: 4)), ["ep-s4e40", "ep-s4e39"])
        XCTAssertEqual(episodeIDs(.init(title: "devils rain", season: 4, episode: 39)), ["ep-s4e39"])
    }

    func testValidationDropsOutOfRangeSwapsRoundsAndNullsUnknowns() {
        let f = NLSearch.validated(.init(
            title: "  The Thing ", kind: .any, yearMin: 2300, yearMax: 1700, genre: "horror", category: "Listener Picks",
            provider: "Blockbuster", ratingMin: 7, ratingMax: 0.2, watched: .any, season: 0, episode: -3
        ), catalog: catalog)
        XCTAssertEqual(f.title, "The Thing")
        XCTAssertNil(f.kind)
        XCTAssertNil(f.yearMin, "2300 is dropped, not clamped")
        XCTAssertNil(f.yearMax, "1700 is dropped, not clamped")
        XCTAssertEqual(f.genre, "Horror")
        XCTAssertEqual(f.category, "Listeners")
        XCTAssertNil(f.provider)
        XCTAssertNil(f.ratingMin, "7 is dropped, not clamped")
        XCTAssertNil(f.ratingMax, "0.2 is dropped, not clamped")
        XCTAssertNil(f.watched)
        XCTAssertNil(f.season)
        XCTAssertNil(f.episode)
        XCTAssertEqual(NLSearch.validated(.init(ratingMin: 4.3), catalog: catalog).ratingMin, 4.5)
        XCTAssertNil(NLSearch.validated(.init(genre: "Science Fiction"), catalog: catalog).genre)
        XCTAssertNil(NLSearch.validated(.init(category: "Animation"), catalog: catalog).category)
        XCTAssertEqual(NLSearch.validated(.init(category: "Criterion & Classics"), catalog: catalog).category, "Criterion")
        XCTAssertEqual(NLSearch.validated(.init(provider: "Disney+"), catalog: catalog).provider, "Disney+")
        XCTAssertEqual(NLSearch.validated(.init(provider: "Max"), catalog: catalog).provider, "Max")
    }

    func testOutOfRangeBoundsDropOnTheirOwnAndRoundTiesAway() {
        func v(_ f: NLSearchFilter) -> NLSearchFilter { NLSearch.validated(f, catalog: catalog) }
        XCTAssertEqual(v(.init(yearMin: 1880, yearMax: 2100)).yearMin, 1880)
        XCTAssertEqual(v(.init(yearMin: 1880, yearMax: 2100)).yearMax, 2100)
        XCTAssertNil(v(.init(yearMin: 1879)).yearMin)
        XCTAssertNil(v(.init(yearMax: 2101)).yearMax)
        XCTAssertEqual(v(.init(yearMin: 1700, yearMax: 1985)).yearMax, 1985)
        XCTAssertNil(v(.init(ratingMin: .nan)).ratingMin)
        XCTAssertNil(v(.init(ratingMax: .infinity)).ratingMax)
        XCTAssertNil(v(.init(ratingMin: 0.4)).ratingMin, "checked before rounding")
        XCTAssertNil(v(.init(ratingMax: 5.2)).ratingMax, "checked before rounding")
        XCTAssertEqual(v(.init(ratingMin: 0.5)).ratingMin, 0.5)
        XCTAssertEqual(v(.init(ratingMin: 3.25)).ratingMin, 3.5, "ties away from zero")
        XCTAssertEqual(v(.init(ratingMin: 4.75)).ratingMin, 5)
        XCTAssertEqual(v(.init(ratingMin: 4.2)).ratingMin, 4)
        let swapped = v(.init(ratingMin: 4.5, ratingMax: 2))
        XCTAssertEqual(swapped.ratingMin, 2)
        XCTAssertEqual(swapped.ratingMax, 4.5)
        XCTAssertEqual(v(.init(ratingMin: 4, unrated: false)).unrated, false, "rated flag kept with a bound")
        XCTAssertNil(v(.init(ratingMin: 4, unrated: true)).ratingMin)
    }

    func testProviderMinimumLength() {
        XCTAssertFalse(NLSearch.providerNameMatches("HBO Max", "a"))
        XCTAssertFalse(NLSearch.providerNameMatches("HBO Max", ""))
        XCTAssertTrue(NLSearch.providerNameMatches("Tubi TV", "tv"), "2-character whole string")
        XCTAssertTrue(NLSearch.providerNameMatches("HBO Max", "max hbo"), "every word, all 2+")
        XCTAssertFalse(NLSearch.providerNameMatches("HBO Max", "max a"), "a word under 2 blocks the fallback")
        XCTAssertFalse(NLSearch.providerNameMatches("HBO Max", "hbo x"), "shared case: 'x' blocks the fallback")
        // The real catalog has HBO Max Amazon Channel, where 'max a' is a whole-string hit.
        XCTAssertTrue(NLSearch.providerNameMatches("HBO Max Amazon Channel", "max a"))
        XCTAssertTrue(NLSearch.providerNameMatches("Criterion Channel", "criterion channel"))
    }

    func testChipsOnePerFieldAndRemovalChangesResults() {
        let f = NLSearch.validated(.init(title: "The Thing", kind: .movie, yearMin: 1980, yearMax: 1989, genre: "Horror",
                                         category: "Cult", provider: "Tubi", freeOnly: true, ratingMin: 4,
                                         watched: .unwatched, season: 3, episode: 10, onMyServices: true), catalog: catalog)
        XCTAssertEqual(NLSearch.chips(for: f, catalog: catalog).map(\.label), [
            "Title: The Thing", "S3E10", "1980–1989", "Horror", "Cult & Bizarre", "Free", "On Tubi",
            "4★ and up", "Unwatched", "On my services",
        ])
        let horror80s = NLSearch.validated(.init(yearMin: 1980, yearMax: 1989, genre: "Horror"), catalog: catalog)
        XCTAssertEqual(movieIDs(horror80s), ["hellraiser-1987", "the-evil-dead-1981", "the-shining-1980", "the-thing-1982"])
        let noYears = NLSearch.removing(.years, from: horror80s)
        XCTAssertNil(noYears.yearMin)
        XCTAssertNil(noYears.yearMax)
        XCTAssertEqual(movieIDs(noYears).count, 6)
        XCTAssertEqual(NLSearch.chips(for: noYears, catalog: catalog).map(\.label), ["Horror"])
        XCTAssertEqual(NLSearch.chips(for: .init(ratingMin: 3, ratingMax: 4.5), catalog: catalog).map(\.label), ["3–4.5★"])
        XCTAssertEqual(NLSearch.chips(for: .init(ratingMin: 5, ratingMax: 5), catalog: catalog).map(\.label), ["Rated 5★"])
        XCTAssertEqual(NLSearch.chips(for: .init(unrated: true), catalog: catalog).map(\.label), ["Unrated"])
        XCTAssertEqual(NLSearch.chips(for: .init(kind: .episode), catalog: catalog), [], "kind only picks the list")
    }

    func testQuestionDetection() {
        let titles = catalog.movies.map(\.title) + ["What Dreams May Come", "Time After Time"]
        for q in ["the thing", "Shudder", "???", "", "alien", "Eternal Sunshine of the Spotless Mind", "what dreams may",
                  "Time After Time", "thing 1982"] {
            XCTAssertFalse(NLSearch.looksLikeQuestion(q, titles: titles), q)
        }
        for q in ["80s horror", "1980s horror", "free", "on Shudder", "S4E39", "4x39", "season 4", "movies",
                  "something scary to watch tonight", "rated 4 stars", "what's on"] {
            XCTAssertTrue(NLSearch.looksLikeQuestion(q, titles: titles), q)
        }
    }

    func testSwitchRule() {
        XCTAssertEqual(NLSearch.listSwitch(kind: .episode, showing: .movies), .switchTo(.episodes))
        XCTAssertEqual(NLSearch.listSwitch(kind: .movie, showing: .episodes), .switchTo(.movies))
        XCTAssertEqual(NLSearch.listSwitch(kind: .movie, showing: .movies), .stay)
        XCTAssertEqual(NLSearch.listSwitch(kind: .episode, showing: .episodes), .stay)
        XCTAssertEqual(NLSearch.listSwitch(kind: .any, showing: .movies), .stay)
        XCTAssertEqual(NLSearch.listSwitch(kind: nil, showing: .episodes), .stay)
    }

    /// The bundled 184-movie catalog: provider variants and vocabulary are real.
    func testBundledCatalogVocabularyAndProviderVariants() throws {
        let url = try XCTUnwrap(Self.bundledCatalogURL())
        let bundled = try JSONDecoder().decode(MovieCatalog.self, from: Data(contentsOf: url))
        XCTAssertEqual(Set(bundled.movies.map(\.genre)), Set(NLSearch.genres))
        XCTAssertEqual(Set(bundled.categories.map(\.id)), Set(NLSearch.categories.map(\.id)))
        let names = NLSearch.streamAndFreeProviderNames(bundled)
        XCTAssertTrue(names.contains("Shudder"))
        XCTAssertNil(NLSearch.validated(.init(provider: "Vudu"), catalog: bundled).provider, "rent-only")
        XCTAssertNil(NLSearch.validated(.init(provider: "Blockbuster"), catalog: bundled).provider)
        for p in ["Shudder", "Tubi", "Pluto", "Disney+", "Max", "Netflix"] {
            XCTAssertNotNil(NLSearch.validated(.init(provider: p), catalog: bundled).provider, p)
        }
        let shudder = NLSearch.apply(.init(provider: "Shudder"), toMovies: bundled.movies, catalog: bundled,
                                     ratings: PersonalRatings(), services: MyServices()).movies
        let direct = bundled.movies.filter { m in
            (m.streaming.map { $0.stream + $0.free } ?? []).contains { CatalogSearch.fold($0.name).contains("shudder") }
        }
        XCTAssertEqual(Set(shudder.map(\.id)), Set(direct.map(\.id)))
        XCTAssertFalse(shudder.isEmpty)
    }

    static func bundledCatalogURL() -> URL? {
        if let url = Bundle.main.url(forResource: "movies", withExtension: "json") { return url }
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MovieRouletteTuesday/Resources/movies.json")
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }
}
