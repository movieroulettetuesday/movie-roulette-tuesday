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

    func testClearRatingKeepsStatusAndDropsOutOfTheAverage() {
        var r = PersonalRatings()
        let t0 = Date(timeIntervalSinceReferenceDate: 10)
        let t1 = Date(timeIntervalSinceReferenceDate: 20)
        r.setHalfStars(8, for: "a", now: t0)          // 4 stars
        r.setHalfStars(1, for: "b", now: t0)          // half a star still rates
        r.setStatus(.wantToWatch, for: "c", now: t0)
        r.setHalfStars(nil, for: "b", now: t1)
        XCTAssertNil(r.halfStars(for: "b"))
        XCTAssertNil(r.rating(for: "b"))
        XCTAssertEqual(r.status(for: "b"), .watched, "clear does not change watched")
        XCTAssertEqual(r.entry(for: "b")?.updatedAt, t1)
        XCTAssertEqual(r.halfStars(for: "a"), 8, "another movie's half-star rating stays")
        XCTAssertEqual(r.status(for: "c"), .wantToWatch)
        XCTAssertEqual(r.watchlist, ["c"])
        XCTAssertEqual(r.watched, ["a", "b"])
        let summary = PersonalRatingsSummary(ratings: r, catalog: nil)
        XCTAssertEqual(summary.ratedCount, 1)
        XCTAssertEqual(summary.averageStars!, 4, accuracy: 1e-12)
        XCTAssertEqual(summary.topRated.map(\.movieId), ["a"])
        XCTAssertNil(PersonalRatingsSummary(ratings: {
            var cleared = PersonalRatings()
            cleared.setHalfStars(8, for: "a", now: t0)
            cleared.setHalfStars(nil, for: "a", now: t1)
            return cleared
        }(), catalog: nil).averageStars, "an unrated movie is not a zero in the average")
        let movies = [
            Movie(id: "a", title: "Alpha", year: 2000, genre: "G"),
            Movie(id: "b", title: "Bravo", year: 2001, genre: "G"),
            Movie(id: "c", title: "Charlie", year: 2002, genre: "G"),
        ]
        let stats = SpinStats(history: [SpinResult(movieId: "b", categoryId: "x")])
        XCTAssertEqual(MovieListFilter.rated.apply(to: movies, ratings: r, spinStats: stats).map(\.id), ["a"])
        XCTAssertEqual(MovieListFilter.watched.apply(to: movies, ratings: r, spinStats: stats).map(\.id), ["a", "b"])
        XCTAssertEqual(MovieListFilter.watchlist.apply(to: movies, ratings: r, spinStats: stats).map(\.id), ["c"])
        XCTAssertEqual(stats.spinCount(forMovie: "b"), 1, "clear does not touch spin history")
    }

    func testClearedRatingSurvivesReloadAndIgnoresLeftoverStars() throws {
        let resurrect = #"{"entries":{"a":{"halfStars":null,"rating":5,"status":"watched","updatedAt":0},"b":{"halfStars":0,"rating":4,"status":"wantToWatch","updatedAt":0},"c":{"halfStars":"nope","rating":3,"status":"watched","updatedAt":0}}}"#
        let decoded = try JSONDecoder().decode(PersonalRatings.self, from: Data(resurrect.utf8))
        XCTAssertNil(decoded.halfStars(for: "a"), "null halfStars wins over a leftover whole-star rating")
        XCTAssertNil(decoded.rating(for: "a"))
        XCTAssertEqual(decoded.status(for: "a"), .watched)
        XCTAssertNil(decoded.halfStars(for: "b"), "0 is unrated, not a rated zero")
        XCTAssertEqual(decoded.status(for: "b"), .wantToWatch)
        XCTAssertEqual(decoded.halfStars(for: "c"), 6, "a non-numeric halfStars still reads the legacy stars")

        var live = PersonalRatings()
        live.setHalfStars(7, for: "a", now: Date(timeIntervalSinceReferenceDate: 1))
        live.setStatus(.wantToWatch, for: "b", now: Date(timeIntervalSinceReferenceDate: 1))
        live.setHalfStars(nil, for: "a", now: Date(timeIntervalSinceReferenceDate: 2))
        let data = try JSONEncoder().encode(live)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let a = try XCTUnwrap((json["entries"] as? [String: Any])?["a"] as? [String: Any])
        XCTAssertTrue(a["halfStars"] is NSNull)
        XCTAssertNil(a["rating"], "the old whole-star field is omitted so it cannot come back")
        XCTAssertEqual(a["status"] as? String, "watched")
        let back = try JSONDecoder().decode(PersonalRatings.self, from: data)
        XCTAssertNil(back.halfStars(for: "a"))
        XCTAssertEqual(back.status(for: "a"), .watched)
        XCTAssertEqual(back.status(for: "b"), .wantToWatch)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("personal-ratings.json")
        let file = PersonalRatingsFileStore(fileURL: url)
        try file.save(live)
        let reloaded = try file.load()
        XCTAssertNil(reloaded.halfStars(for: "a"))
        XCTAssertEqual(reloaded.status(for: "a"), .watched)
        XCTAssertEqual(reloaded.halfStars(for: "b"), nil)
        XCTAssertEqual(reloaded.status(for: "b"), .wantToWatch)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    func testStoreClearSurvivesRelaunch() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("personal-ratings.json")
        await MainActor.run {
            let first = PersonalRatingsStore(fileStore: PersonalRatingsFileStore(fileURL: url))
            first.setHalfStars(7, for: "a")
            first.setStatus(.wantToWatch, for: "b")
            first.setHalfStars(nil, for: "a")
            let second = PersonalRatingsStore(fileStore: PersonalRatingsFileStore(fileURL: url))
            XCTAssertNil(second.halfStars(for: "a"))
            XCTAssertNil(second.rating(for: "a"))
            XCTAssertEqual(second.status(for: "a"), .watched)
            XCTAssertEqual(second.status(for: "b"), .wantToWatch)
            XCTAssertNil(second.halfStars(for: "b"))
        }
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    func testClearRatingCopyIsStable() {
        XCTAssertEqual(RatingClearAction.title, "Clear rating")
        XCTAssertEqual(RatingClearAction.accessibilityLabel, "Clear rating")
        XCTAssertEqual(RatingClearAction.accessibilityIdentifier, "clear-rating")
        XCTAssertEqual(RatingClearAction.tvAccessibilityIdentifier, "tv.movie.clearRating")
        XCTAssertTrue(RatingClearAction.accessibilityHint.contains("Watched"))
        XCTAssertFalse(RatingClearAction.accessibilityHint.contains("zero"))
    }
}
