import XCTest
import MRTCore

/// Clear rating on the shared core: unrated is nil, never a stored zero, and a
/// stale listener record is dropped from the average instead of coming back.
final class ClearRatingCoreTests: XCTestCase {
    func testClearKeepsStatusAndLeavesTheAverage() {
        var ratings = PersonalRatings()
        let t0 = Date(timeIntervalSinceReferenceDate: 10)
        let t1 = Date(timeIntervalSinceReferenceDate: 20)
        ratings.setHalfStars(8, for: "a", now: t0)
        ratings.setHalfStars(1, for: "b", now: t0)
        ratings.setStatus(.wantToWatch, for: "c", now: t0)
        ratings.setHalfStars(nil, for: "b", now: t1)
        XCTAssertNil(ratings.halfStars(for: "b"))
        XCTAssertNil(ratings.rating(for: "b"))
        XCTAssertEqual(ratings.status(for: "b"), .watched)
        XCTAssertEqual(ratings.halfStars(for: "a"), 8)
        XCTAssertEqual(ratings.watchlist, ["c"])
        let summary = PersonalRatingsSummary(ratings: ratings, catalog: nil)
        XCTAssertEqual(summary.ratedCount, 1)
        XCTAssertEqual(summary.averageStars!, 4, accuracy: 1e-12)
        XCTAssertNil(PersonalRatingsSummary(ratings: {
            var cleared = PersonalRatings()
            cleared.setHalfStars(8, for: "a", now: t0)
            cleared.setHalfStars(nil, for: "a", now: t1)
            return cleared
        }(), catalog: nil).averageStars)
        XCTAssertEqual(HalfStars.fromLocation(5, width: 100), 1, "half-star taps still bottom out at ½")
    }

    func testClearedFileIgnoresLeftoverStarsAndRoundTrips() throws {
        let resurrect = #"{"entries":{"a":{"halfStars":null,"rating":5,"status":"watched","updatedAt":0},"b":{"halfStars":0,"rating":4,"status":"wantToWatch","updatedAt":0}}}"#
        let decoded = try JSONDecoder().decode(PersonalRatings.self, from: Data(resurrect.utf8))
        XCTAssertNil(decoded.halfStars(for: "a"))
        XCTAssertEqual(decoded.status(for: "a"), .watched)
        XCTAssertNil(decoded.halfStars(for: "b"))
        XCTAssertEqual(decoded.status(for: "b"), .wantToWatch)

        var live = PersonalRatings()
        live.setHalfStars(7, for: "a", now: Date(timeIntervalSinceReferenceDate: 1))
        live.setHalfStars(nil, for: "a", now: Date(timeIntervalSinceReferenceDate: 2))
        let data = try JSONEncoder().encode(live)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entry = try XCTUnwrap((json["entries"] as? [String: Any])?["a"] as? [String: Any])
        XCTAssertTrue(entry["halfStars"] is NSNull)
        XCTAssertNil(entry["rating"])
        let suite = "mrt-clear-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(data, forKey: "tv.personalRatings")
        let stored = try XCTUnwrap(defaults.data(forKey: "tv.personalRatings"))
        let back = try JSONDecoder().decode(PersonalRatings.self, from: stored)
        XCTAssertNil(back.halfStars(for: "a"))
        XCTAssertEqual(back.status(for: "a"), .watched)
    }

    func testDeleteDropsTheSharedRatingInsteadOfZero() async throws {
        let store = InMemoryCommunityStore(currentUser: "u")
        await store.seedHalfStarRatings(movieId: "m", halfStars: [4])
        let name = try await store.submitRating(movieId: "m", halfStars: 8)
        let deleted = try await store.deleteRating(movieId: "m")
        XCTAssertEqual(deleted, name)
        let mine = try await store.myRating(movieId: "m")
        XCTAssertNil(mine)
        let fetched = try await store.fetchRatings(movieId: "m")
        XCTAssertNil(fetched[name])
        let aggregate = RatingAggregate.from(halfStars: fetched.values)
        XCTAssertEqual(aggregate.count, 1)
        XCTAssertEqual(aggregate.average!, 2, accuracy: 1e-12)
        XCTAssertNotEqual(aggregate.average, 0)
        let stale = CommunityMerge.removing(["mine": 8, "other": 4], recordNames: ["mine"])
        XCTAssertEqual(RatingAggregate.from(halfStars: stale.values), RatingAggregate.from(halfStars: [0, 4]))
        XCTAssertNil(RatingAggregate.from(halfStars: [0]).average)
        XCTAssertEqual(RatingClearAction.title, "Clear rating")
        XCTAssertEqual(RatingClearAction.tvAccessibilityIdentifier, "tv.movie.clearRating")
    }
}
