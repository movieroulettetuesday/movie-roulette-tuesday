import XCTest
@testable import MovieRouletteTuesday

final class PersonalRatingsTests: XCTestCase {
    private let catalog = MovieCatalog(categories: [], movies: [
        Movie(id: "a", title: "Alpha", year: 2000, genre: "G"),
        Movie(id: "b", title: "Bravo", year: 2001, genre: "G", hostRating: 4),
        Movie(id: "c", title: "Charlie", year: 2002, genre: "G"),
    ])

    func testSetRatingClampsAndImpliesWatched() {
        var r = PersonalRatings()
        r.setRating(9, for: "a")
        XCTAssertEqual(r.rating(for: "a"), 5)
        XCTAssertEqual(r.status(for: "a"), .watched)
        r.setStatus(.wantToWatch, for: "b")
        XCTAssertEqual(r.watchlist, ["b"])
        r.setRating(3, for: "b")
        XCTAssertEqual(r.status(for: "b"), .watched)
        r.setRating(0, for: "a")
        XCTAssertNil(r.rating(for: "a"))
        XCTAssertEqual(r.status(for: "a"), .watched) // status kept
        r.setStatus(nil, for: "a")
        XCTAssertNil(r.entry(for: "a")) // empty entries are pruned
    }

    func testFileStoreRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("personal-ratings.json")
        let store = PersonalRatingsFileStore(fileURL: url)
        XCTAssertEqual(try store.load(), PersonalRatings())
        var r = PersonalRatings()
        r.setRating(4, for: "a", now: Date(timeIntervalSinceReferenceDate: 1000))
        r.setStatus(.wantToWatch, for: "c", now: Date(timeIntervalSinceReferenceDate: 2000))
        try store.save(r)
        XCTAssertEqual(try store.load(), r)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    func testSummary() {
        var r = PersonalRatings()
        r.setRating(5, for: "c")
        r.setRating(2, for: "b")
        r.setRating(5, for: "a")
        r.setStatus(.wantToWatch, for: "zzz-gone")
        let s = PersonalRatingsSummary(ratings: r, catalog: catalog, topLimit: 2)
        XCTAssertEqual(s.ratedCount, 3)
        XCTAssertEqual(s.averageStars!, 4, accuracy: 1e-12)
        XCTAssertEqual(s.topRated.map(\.title), ["Alpha", "Charlie"])
        XCTAssertEqual(s.versusHosts.map(\.movieId), ["b"]) // only where hostRating exists
        XCTAssertEqual(s.averageDifferenceFromHosts!, -2, accuracy: 1e-12)
        XCTAssertEqual(s.watchlistCount, 1)
        XCTAssertEqual(s.watchedCount, 3)
        let empty = PersonalRatingsSummary(ratings: PersonalRatings(), catalog: catalog)
        XCTAssertNil(empty.averageStars)
        XCTAssertNil(empty.averageDifferenceFromHosts)
    }

    func testMovieListFilters() {
        var r = PersonalRatings()
        r.setStatus(.wantToWatch, for: "a")
        r.setRating(4, for: "b")
        let stats = SpinStats(history: [SpinResult(movieId: "b", categoryId: "x"), SpinResult(movieId: "c", categoryId: "x")])
        let movies = catalog.movies
        XCTAssertEqual(MovieListFilter.all.apply(to: movies, ratings: r, spinStats: stats).map(\.id), ["a", "b", "c"])
        XCTAssertEqual(MovieListFilter.watchlist.apply(to: movies, ratings: r, spinStats: stats).map(\.id), ["a"])
        XCTAssertEqual(MovieListFilter.watched.apply(to: movies, ratings: r, spinStats: stats).map(\.id), ["b"])
        XCTAssertEqual(MovieListFilter.rated.apply(to: movies, ratings: r, spinStats: stats).map(\.id), ["b"])
        XCTAssertEqual(MovieListFilter.notSpunYet.apply(to: movies, ratings: r, spinStats: stats).map(\.id), ["a"])
    }

    func testNewEpisodeBadge() {
        let d = { (s: Double) in Date(timeIntervalSince1970: s) }
        let eps = [
            PodcastEpisode(guid: "1", title: "1", pubDate: d(100)),
            PodcastEpisode(guid: "2", title: "2", pubDate: d(200)),
            PodcastEpisode(guid: "3", title: "3", pubDate: nil),
        ]
        XCTAssertEqual(NewEpisodeBadge.count(episodes: eps, lastViewed: nil), 0)
        XCTAssertEqual(NewEpisodeBadge.count(episodes: eps, lastViewed: d(150)), 1)
        XCTAssertEqual(NewEpisodeBadge.count(episodes: eps, lastViewed: d(200)), 0)
        let baseline = NewEpisodeBadge.initialBaseline(episodes: eps, now: d(999))
        XCTAssertEqual(baseline, d(200))
        XCTAssertEqual(NewEpisodeBadge.count(episodes: eps, lastViewed: baseline), 0) // first launch: no badge
        XCTAssertEqual(NewEpisodeBadge.initialBaseline(episodes: [], now: d(5)), d(5))
        XCTAssertEqual(NewEpisodeBadge.viewedTimestamp(episodes: eps, now: d(150)), d(200))
        XCTAssertEqual(NewEpisodeBadge.viewedTimestamp(episodes: eps, now: d(300)), d(300))
    }
}
