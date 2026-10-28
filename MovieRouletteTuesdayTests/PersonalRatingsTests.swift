import XCTest
@testable import MovieRouletteTuesday
import MRTCore

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


final class HalfStarMappingTests: XCTestCase {
    func testLocationMapping() {
        let w = 100.0  // 5 stars, 20 pt each
        XCTAssertEqual(HalfStars.fromLocation(0, width: w), 1)
        XCTAssertEqual(HalfStars.fromLocation(5, width: w), 1)     // left half of star 1
        XCTAssertEqual(HalfStars.fromLocation(15, width: w), 2)    // right half of star 1
        XCTAssertEqual(HalfStars.fromLocation(65, width: w), 7)    // left half of star 4 = 3.5
        XCTAssertEqual(HalfStars.fromLocation(75, width: w), 8)
        XCTAssertEqual(HalfStars.fromLocation(250, width: w), 10)  // dragged past the end
        XCTAssertEqual(HalfStars.fromLocation(-30, width: w), 1)
        XCTAssertEqual(HalfStars.fromLocation(50, width: 0), 1)
    }

    func testFillAndLabels() {
        XCTAssertEqual((1...5).map { HalfStars.fill(star: $0, halfStars: 7) }, [1, 1, 1, 0.5, 0])
        XCTAssertEqual((1...5).map { HalfStars.fill(star: $0, halfStars: nil) }, [0, 0, 0, 0, 0])
        XCTAssertEqual(HalfStars.label(7), "3.5")
        XCTAssertEqual(HalfStars.label(8), "4")
        XCTAssertEqual(HalfStars.label(stars: 4.26), "4.5")
        XCTAssertEqual(HalfStars.label(stars: 4.24), "4")
        XCTAssertEqual(HalfStars.roundedToHalf(3.74), 3.5)
        XCTAssertEqual(HalfStars.roundedToHalf(3.75), 4.0)
    }

    func testRoundingForOlderBuilds() {
        XCTAssertEqual((1...10).map(HalfStars.roundedStars), [1, 1, 2, 2, 3, 3, 4, 4, 5, 5])
        XCTAssertEqual(HalfStars.clamped(0), nil)
        XCTAssertEqual(HalfStars.clamped(14), 10)
        XCTAssertEqual(HalfStars.fromLegacyStars(3), 6)
        XCTAssertEqual(HalfStars.fromLegacyStars(9), 10)
        XCTAssertNil(HalfStars.fromLegacyStars(0))
        XCTAssertEqual(HalfStars.resolved(halfStars: 7, legacyStars: 4), 7)
        XCTAssertEqual(HalfStars.resolved(halfStars: nil, legacyStars: 4), 8)
        XCTAssertNil(HalfStars.resolved(halfStars: nil, legacyStars: nil))
    }

    func testVoiceOverAdjustSteps() {
        XCTAssertEqual(HalfStars.adjusted(nil, increment: true), 1)
        XCTAssertEqual(HalfStars.adjusted(7, increment: true), 8)
        XCTAssertEqual(HalfStars.adjusted(10, increment: true), 10)
        XCTAssertEqual(HalfStars.adjusted(7, increment: false), 6)
        XCTAssertNil(HalfStars.adjusted(1, increment: false))
    }

    func testLegacyPersonalFileMigratesInPlace() throws {
        let legacy = #"{"entries":{"a":{"rating":4,"status":"watched","updatedAt":0},"b":{"status":"wantToWatch","updatedAt":0}}}"#
        var r = try JSONDecoder().decode(PersonalRatings.self, from: Data(legacy.utf8))
        XCTAssertEqual(r.halfStars(for: "a"), 8)
        XCTAssertEqual(r.rating(for: "a"), 4)
        XCTAssertNil(r.halfStars(for: "b"))
        r.setHalfStars(7, for: "a", now: Date(timeIntervalSinceReferenceDate: 5))
        let data = try JSONEncoder().encode(r)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let a = try XCTUnwrap((json["entries"] as? [String: Any])?["a"] as? [String: Any])
        XCTAssertEqual(a["halfStars"] as? Int, 7)
        XCTAssertEqual(a["rating"] as? Int, 4, "rounded stars kept for a downgrade")
        let back = try JSONDecoder().decode(PersonalRatings.self, from: data)
        XCTAssertEqual(back.halfStars(for: "a"), 7)
    }

    func testSummaryUsesHalfStars() {
        var r = PersonalRatings()
        r.setHalfStars(7, for: "a")
        r.setHalfStars(10, for: "b")
        r.setHalfStars(0, for: "c")
        let s = PersonalRatingsSummary(ratings: r, catalog: nil)
        XCTAssertEqual(s.ratedCount, 2)
        XCTAssertEqual(s.averageStars!, 4.25, accuracy: 1e-12)
        XCTAssertEqual(s.topRated.map(\.movieId), ["b", "a"])
        XCTAssertEqual(s.topRated.last?.halfStars, 7)
        XCTAssertEqual(r.status(for: "a"), .watched, "rating implies watched")
    }

    /// Apple TV stores ratings in UserDefaults (Application Support can be purged).
    @MainActor
    func testUserDefaultsRoundTrip() throws {
        let suite = "tv-ratings-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PersonalRatingsStore(fileStore: nil, defaults: defaults)
        store.setHalfStars(8, for: "a")
        store.setStatus(.wantToWatch, for: "b")
        let again = PersonalRatingsStore(fileStore: nil, defaults: defaults)
        XCTAssertEqual(again.halfStars(for: "a"), 8)
        XCTAssertEqual(again.status(for: "b"), .wantToWatch)
        XCTAssertEqual(again.status(for: "a"), .watched)
    }
}
