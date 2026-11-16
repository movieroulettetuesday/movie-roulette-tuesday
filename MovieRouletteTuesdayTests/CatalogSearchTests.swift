import XCTest
@testable import MovieRouletteTuesday

/// The shared search matcher: lists, the TV Search tab, and Siri all use it.
final class CatalogSearchTests: XCTestCase {
    private var catalog: MovieCatalog!
    private var episodes: [PodcastEpisode]!
    private var byGUID: [String: PodcastEpisode]!
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    override func setUp() {
        super.setUp()
        catalog = Self.makeCatalog()
        episodes = Self.makeEpisodes()
        byGUID = Dictionary(uniqueKeysWithValues: episodes.map { ($0.guid, $0) })
    }

    private func movieIDs(_ query: String) -> [String] {
        CatalogSearch.movies(catalog.movies, matching: query, catalog: catalog, episodesByGUID: byGUID).map(\.movie.id)
    }

    private func movieRanks(_ query: String) -> [String: CatalogSearch.Rank] {
        Dictionary(uniqueKeysWithValues: CatalogSearch.movies(catalog.movies, matching: query, catalog: catalog, episodesByGUID: byGUID)
            .map { ($0.movie.id, $0.rank) })
    }

    private func episodeIDs(_ query: String) -> [String] {
        CatalogSearch.episodes(episodes, matching: query, catalog: catalog, calendar: utc).map(\.episode.guid)
    }

    func testFoldHandlesCaseAccentsApostrophesAndPunctuation() {
        XCTAssertEqual(CatalogSearch.fold("The Devil’s Rain"), "the devils rain")
        XCTAssertEqual(CatalogSearch.fold("THE DEVIL'S RAIN"), "the devils rain")
        XCTAssertEqual(CatalogSearch.fold("Amélie"), "amelie")
        XCTAssertEqual(CatalogSearch.fold("  Spider-Man:  Far…  "), "spider man far")
        XCTAssertEqual(CatalogSearch.fold("π"), "π")
    }

    func testCaseInsensitive() {
        XCTAssertEqual(movieIDs("DEVILS RAIN"), ["the-devils-rain-1975"])
        XCTAssertEqual(movieIDs("devils rain"), ["the-devils-rain-1975"])
        XCTAssertEqual(movieRanks("devils rain")["the-devils-rain-1975"], .exactTitle)
    }

    func testAccentsFoldBothWays() {
        XCTAssertEqual(movieIDs("amelie"), ["amelie-2001"])
        XCTAssertEqual(movieIDs("AMÉLIE"), ["amelie-2001"])
    }

    func testStraightAndCurlyApostrophes() {
        XCTAssertEqual(movieIDs("devil's rain"), ["the-devils-rain-1975"])
        XCTAssertEqual(movieIDs("devil’s rain"), ["the-devils-rain-1975"])
        XCTAssertEqual(movieIDs("del toros pinocchio"), ["pinocchio-2022"])
        XCTAssertEqual(movieIDs("del toro's pinocchio"), ["pinocchio-2022"])
    }

    func testLeadingTheIsIgnored() {
        XCTAssertEqual(movieIDs("thing"), ["the-thing-1982", "the-thing-2011"])
        XCTAssertEqual(movieIDs("The Thing"), ["the-thing-1982", "the-thing-2011"])
        XCTAssertEqual(movieRanks("thing")["the-thing-1982"], .exactTitle)
        XCTAssertEqual(movieRanks("a space odyssey")["2001-a-space-odyssey-1968"], .titleWords)
    }

    func testPartialMatches() {
        XCTAssertEqual(movieRanks("devil")["the-devils-rain-1975"], .titlePrefix)
        XCTAssertEqual(movieRanks("rain devils")["the-devils-rain-1975"], .titleWords)
        XCTAssertEqual(movieIDs("thi"), ["the-thing-1982", "the-thing-2011"])
    }

    func testYearDisambiguatesAndYearOnlyQueries() {
        XCTAssertEqual(movieIDs("The Thing 1982"), ["the-thing-1982"])
        XCTAssertEqual(movieIDs("thing 2011"), ["the-thing-2011"])
        XCTAssertEqual(movieIDs("1982"), ["the-thing-1982"])
        XCTAssertEqual(movieRanks("1982")["the-thing-1982"], .year)
        // A year that is also in a title: the title match ranks first.
        XCTAssertEqual(movieIDs("2001"), ["2001-a-space-odyssey-1968", "amelie-2001"])
        XCTAssertEqual(movieRanks("2001")["2001-a-space-odyssey-1968"], .titlePrefix)
        XCTAssertEqual(movieRanks("2001")["amelie-2001"], .year)
    }

    func testSeasonEpisodeForms() {
        for form in ["S4E39", "s4e39", "s4 e39", "4x39", "season 4 episode 39"] {
            XCTAssertEqual(movieIDs(form), ["the-devils-rain-1975"], form)
            XCTAssertEqual(episodeIDs(form), ["Buzzsprout-20099500"], form)
        }
        XCTAssertEqual(movieRanks("S4E39")["the-devils-rain-1975"], .episode)
        XCTAssertEqual(episodeIDs("episode 40"), ["Buzzsprout-3"])
        XCTAssertEqual(episodeIDs("ep 38"), ["Buzzsprout-2"])
        XCTAssertEqual(episodeIDs("e38"), ["Buzzsprout-2"])
        XCTAssertEqual(episodeIDs("S4E39 rain"), ["Buzzsprout-20099500"])
        XCTAssertTrue(episodeIDs("S9E99").isEmpty)
        XCTAssertTrue(movieIDs("S9E99").isEmpty)
    }

    func testProviderIsASecondaryMatch() {
        let hits = CatalogSearch.movies(catalog.movies, matching: "shudder", catalog: catalog, episodesByGUID: byGUID)
        XCTAssertEqual(hits.map(\.movie.id), ["the-shudder-1990", "the-devils-rain-1975"])
        XCTAssertEqual(hits.map(\.rank), [.exactTitle, .provider])
        // Genre outranks provider; title outranks both.
        XCTAssertLessThan(CatalogSearch.Rank.titleWords, .episode)
        XCTAssertLessThan(CatalogSearch.Rank.episode, .year)
        XCTAssertLessThan(CatalogSearch.Rank.year, .genreOrCategory)
        XCTAssertLessThan(CatalogSearch.Rank.genreOrCategory, .provider)
        // Rent / buy lists are not searched (too noisy).
        XCTAssertTrue(movieIDs("vudu").isEmpty)
    }

    func testGenreCategoryAndEpisodeTitleMatches() {
        XCTAssertEqual(movieRanks("horror")["the-thing-1982"], .genreOrCategory)
        XCTAssertEqual(movieRanks("Cult Classics")["the-devils-rain-1975"], .genreOrCategory)
        XCTAssertEqual(movieRanks("puppet masters")["pinocchio-2022"], .episode)
    }

    func testEpisodesMatchTitleLinkedMovieGenreAndProvider() {
        let hits = CatalogSearch.episodes(episodes, matching: "devils rain", catalog: catalog, calendar: utc)
        XCTAssertEqual(hits.map(\.episode.guid), ["Buzzsprout-20099500"])
        XCTAssertEqual(hits.first?.rank, .exactTitle)
        let linked = CatalogSearch.episodes(episodes, matching: "guillermo", catalog: catalog, calendar: utc)
        XCTAssertEqual(linked.map(\.episode.guid), ["Buzzsprout-2"])
        XCTAssertEqual(linked.first?.rank, .episode)
        XCTAssertEqual(episodeIDs("horror"), ["Buzzsprout-20099500"])
        XCTAssertEqual(episodeIDs("shudder"), ["Buzzsprout-20099500"])
        XCTAssertEqual(episodeIDs("2025"), ["Buzzsprout-3", "Buzzsprout-20099500", "Buzzsprout-2"], "newest first within a rank")
    }

    func testNoMatchAndUnicodeTitles() {
        XCTAssertTrue(movieIDs("zzzz-not-a-movie").isEmpty)
        XCTAssertTrue(episodeIDs("zzzz-not-an-episode").isEmpty)
        XCTAssertEqual(movieIDs("π"), ["pi-1998"])
        XCTAssertFalse(movieIDs("pi").contains("pi-1998"), "Unicode folding does not turn pi into π")
    }

    func testHostsAreNotSearched() {
        XCTAssertEqual(catalog.showInfo.hosts, ["Rachael", "Karl", "Matt"])
        XCTAssertTrue(movieIDs("karl").isEmpty)
        XCTAssertTrue(episodeIDs("rachael").isEmpty)
    }

    func testEmptyQueryReturnsNothing() {
        for query in ["", "   ", "!!!", "’"] {
            XCTAssertTrue(movieIDs(query).isEmpty, "movies for \(query)")
            XCTAssertTrue(episodeIDs(query).isEmpty, "episodes for \(query)")
            XCTAssertTrue(CatalogSearch.Query(query).isEmpty, query)
        }
    }

    // MARK: Fixture

    static func makeCatalog() -> MovieCatalog {
        let horror = RouletteCategory(
            id: "cat-horror", name: "Horror", colorHex: "#C25B5E",
            movieIds: ["the-devils-rain-1975", "the-thing-1982", "the-thing-2011", "the-shudder-1990"]
        )
        let cult = RouletteCategory(
            id: "cat-cult", name: "Cult", fullName: "Cult Classics", colorHex: "#8670AE",
            movieIds: ["the-devils-rain-1975"]
        )
        let other = RouletteCategory(
            id: "cat-other", name: "Other", colorHex: "#5E8C6A",
            movieIds: ["pinocchio-2022", "amelie-2001", "2001-a-space-odyssey-1968", "pi-1998"]
        )
        let shudder = StreamingInfo.Provider(id: 99, name: "Shudder")
        let netflix = StreamingInfo.Provider(id: 8, name: "Netflix")
        let vudu = StreamingInfo.Provider(id: 7, name: "Vudu")
        let movies = [
            Movie(id: "the-devils-rain-1975", title: "The Devil's Rain", year: 1975, genre: "Horror",
                  categories: ["cat-horror", "cat-cult"], episodeIds: ["Buzzsprout-20099500"],
                  episodeTitle: "The Devil's Rain", streaming: StreamingInfo(stream: [shudder, netflix], rent: [vudu])),
            Movie(id: "the-thing-1982", title: "The Thing", year: 1982, genre: "Horror", categories: ["cat-horror"]),
            Movie(id: "the-thing-2011", title: "The Thing", year: 2011, genre: "Horror", categories: ["cat-horror"]),
            Movie(id: "the-shudder-1990", title: "The Shudder", year: 1990, genre: "Horror", categories: ["cat-horror"]),
            Movie(id: "pinocchio-2022", title: "Guillermo del Toro’s Pinocchio", year: 2022, genre: "Animation",
                  categories: ["cat-other"], episodeIds: ["Buzzsprout-2"], streaming: StreamingInfo(stream: [netflix])),
            Movie(id: "amelie-2001", title: "Amélie", year: 2001, genre: "Romance", categories: ["cat-other"]),
            Movie(id: "2001-a-space-odyssey-1968", title: "2001: A Space Odyssey", year: 1968, genre: "Science Fiction",
                  categories: ["cat-other"]),
            Movie(id: "pi-1998", title: "π", year: 1998, genre: "Thriller", categories: ["cat-other"]),
        ]
        return MovieCatalog(categories: [horror, cult, other], movies: movies)
    }

    static func makeEpisodes() -> [PodcastEpisode] {
        func day(_ text: String) -> Date {
            let formatter = ISO8601DateFormatter()
            return formatter.date(from: text + "T12:00:00Z")!
        }
        return [
            PodcastEpisode(guid: "Buzzsprout-20099500", title: "The Devil's Rain", pubDate: day("2025-11-04"), season: 4, episode: 39,
                           summary: "Karl and Rachael talk Satanists."),
            PodcastEpisode(guid: "Buzzsprout-2", title: "Pinocchio and the Puppet Masters", pubDate: day("2025-10-28"), season: 4, episode: 38),
            PodcastEpisode(guid: "Buzzsprout-3", title: "Bonus: Listener Mailbag", pubDate: day("2025-11-11"), season: 4, episode: 40),
        ]
    }
}
