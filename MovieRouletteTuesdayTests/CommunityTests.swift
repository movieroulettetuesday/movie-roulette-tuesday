import XCTest
@testable import MovieRouletteTuesday
import MRTCore

final class CommunityTests: XCTestCase {
    func testSHA256KnownVectors() {
        XCTAssertEqual(SHA256Digest.hex(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(SHA256Digest.hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(
            SHA256Digest.hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
        )
        XCTAssertEqual(SHA256Digest.hex(String(repeating: "a", count: 1000)).count, 64)
    }

    func testVoteRecordNameIsDeterministicAndAnonymous() {
        let user = "_a1b2c3d4e5f6"
        let a = CommunityRecordNames.vote(pollId: "Buzzsprout-19913482.good-bad", userRecordName: user)
        let b = CommunityRecordNames.vote(pollId: "Buzzsprout-19913482.good-bad", userRecordName: user)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a, "vote-Buzzsprout-19913482.good-bad-" + SHA256Digest.hex(user + "Buzzsprout-19913482.good-bad"))
        XCTAssertFalse(a.contains(user))
        XCTAssertFalse(a.hasPrefix("_"))
        XCTAssertLessThanOrEqual(a.count, 255)
        XCTAssertNotEqual(a, CommunityRecordNames.vote(pollId: "Buzzsprout-19913482.good-bad", userRecordName: "_other"))
        XCTAssertNotEqual(a, CommunityRecordNames.vote(pollId: "Buzzsprout-1.good-bad", userRecordName: user))
        let r = CommunityRecordNames.rating(movieId: "the-room-2003", userRecordName: user)
        XCTAssertEqual(r, CommunityRecordNames.rating(movieId: "the-room-2003", userRecordName: user))
        XCTAssertTrue(r.hasPrefix("rating-the-room-2003-"))
        XCTAssertFalse(r.contains(user))
        // Unsafe ids are hashed into a valid ASCII component.
        let weird = CommunityRecordNames.safeComponent("Épisode 1 / ünïcode")
        XCTAssertTrue(weird.hasPrefix("h"))
        XCTAssertTrue(weird.allSatisfy { $0.isASCII })
    }

    func testDefaultPollsAreDeterministicAndUseHostNames() {
        let hosts = ["Rachael", "Karl", "Matt"]
        let p1 = PollFactory.defaultPoll(forEpisode: "Buzzsprout-19913482", hosts: hosts)
        XCTAssertEqual(p1, PollFactory.defaultPoll(forEpisode: "Buzzsprout-19913482", hosts: hosts))
        let kinds = Set((0..<60).map { PollFactory.defaultKind(forEpisode: "Buzzsprout-\($0)") })
        XCTAssertEqual(kinds.count, 3) // all question types get used across episodes
        let argumentGuid = (0..<200).map { "Buzzsprout-\($0)" }.first { PollFactory.defaultKind(forEpisode: $0) == .argument }!
        let arg = PollFactory.defaultPoll(forEpisode: argumentGuid, hosts: hosts)
        XCTAssertEqual(arg.options.map(\.label), ["Rachael", "Karl", "Matt", "Tie"])
        XCTAssertEqual(PollFactory.defaultPoll(forEpisode: argumentGuid, hosts: []).options.map(\.label), ["Host A", "Host B", "Tie"])
    }

    func testOverrides() throws {
        let json = #"{"polls":[{"episodeGuid":"Buzzsprout-1","question":"Best snack?","options":["Popcorn","Nachos","Candy"]},{"episodeGuid":"Buzzsprout-2","question":"Bad","options":["Only one"]}]}"#
        let overrides = try PollOverrides.decode(Data(json.utf8))
        let p = PollFactory.poll(forEpisode: "Buzzsprout-1", hosts: [], overrides: overrides)
        XCTAssertEqual(p.question, "Best snack?")
        XCTAssertEqual(p.options.map(\.id), ["opt-1", "opt-2", "opt-3"])
        XCTAssertTrue(p.id.hasPrefix("Buzzsprout-1.custom-"))
        // Invalid override (one option) falls back to the default poll.
        XCTAssertEqual(PollFactory.poll(forEpisode: "Buzzsprout-2", hosts: [], overrides: overrides),
                       PollFactory.defaultPoll(forEpisode: "Buzzsprout-2", hosts: []))
        XCTAssertEqual(try PollOverrides.decode(Data(#"{"polls":[]}"#.utf8)).polls.count, 0)
    }

    func testPollTally() {
        let poll = PollDefinition(id: "p", episodeGuid: "e", question: "?",
                                  options: [PollOption(id: "good", label: "Good"), PollOption(id: "bad", label: "Bad")])
        let r = PollResults.tally(poll: poll, votes: ["good", "bad", "good", "good", "bogus"])
        XCTAssertEqual(r.total, 4)
        XCTAssertEqual(r.rows.map(\.count), [3, 1])
        XCTAssertEqual(r.rows[0].fraction, 0.75, accuracy: 1e-12)
        XCTAssertEqual(r.leaders.map(\.id), ["good"])
        let empty = PollResults.tally(poll: poll, votes: [])
        XCTAssertEqual(empty.total, 0)
        XCTAssertEqual(empty.rows.map(\.fraction), [0, 0])
        XCTAssertTrue(empty.leaders.isEmpty)
    }

    func testRatingAggregate() {
        let a = RatingAggregate.from(stars: [5, 4, 4, 0, 6, 1])
        XCTAssertEqual(a.count, 4)
        XCTAssertEqual(a.average!, 3.5, accuracy: 1e-12)
        XCTAssertEqual(a.histogram, [1, 0, 0, 2, 1])
        XCTAssertNil(RatingAggregate.from(stars: []).average)
    }

    func testMergeOwnRecordNeverDoubleCounts() {
        let fetched = ["vote-p-aaa": "good", "vote-p-bbb": "bad"]
        // Own record already indexed with an old value: replaced, not added.
        let replaced = CommunityMerge.merging(fetched, own: (recordName: "vote-p-aaa", value: "bad"))
        XCTAssertEqual(replaced.count, 2)
        XCTAssertEqual(replaced["vote-p-aaa"], "bad")
        // Own record not yet visible to the query: added once.
        let added = CommunityMerge.merging(fetched, own: (recordName: "vote-p-ccc", value: "good"))
        XCTAssertEqual(added.count, 3)
        XCTAssertEqual(CommunityMerge.merging(fetched, own: nil), fetched)
    }

    func testTimedCache() {
        var cache = TimedCache<String, Int>(ttl: 60)
        let t0 = Date(timeIntervalSince1970: 0)
        cache.insert(1, for: "k", now: t0)
        XCTAssertEqual(cache.value(for: "k", now: t0.addingTimeInterval(59)), 1)
        XCTAssertNil(cache.value(for: "k", now: t0.addingTimeInterval(61)))
        XCTAssertEqual(cache.staleValue(for: "k"), 1)
        cache.invalidate("k")
        XCTAssertNil(cache.staleValue(for: "k"))
    }

    func testInMemoryStoreOneVotePerUserAndAggregation() async throws {
        let store = InMemoryCommunityStore(currentUser: "user-1")
        let poll = PollFactory.defaultPoll(forEpisode: "Buzzsprout-42", hosts: ["Rachael", "Karl", "Matt"])
        let first = poll.options[0].id, second = poll.options[1].id
        try await store.submitVote(pollId: poll.id, option: first)
        try await store.submitVote(pollId: poll.id, option: second) // re-vote overwrites
        var names = await store.voteRecordNames
        XCTAssertEqual(names.count, 1)
        let myVote = try await store.myVote(pollId: poll.id)
        XCTAssertEqual(myVote, second)

        await store.setCurrentUser("user-2")
        try await store.submitVote(pollId: poll.id, option: second)
        names = await store.voteRecordNames
        XCTAssertEqual(names.count, 2)
        let results = PollResults.tally(poll: poll, votes: try await store.fetchVotes(pollId: poll.id).values)
        XCTAssertEqual(results.total, 2)
        XCTAssertEqual(results.rows[1].count, 2)

        try await store.submitRating(movieId: "m", halfStars: 8)
        try await store.submitRating(movieId: "m", halfStars: 4)
        await store.setCurrentUser("user-1")
        try await store.submitRating(movieId: "m", halfStars: 10)
        let agg = RatingAggregate.from(halfStars: try await store.fetchRatings(movieId: "m").values)
        XCTAssertEqual(agg.count, 2)
        XCTAssertEqual(agg.average!, 3.5, accuracy: 1e-12)
        let mine = try await store.myRating(movieId: "m")
        XCTAssertEqual(mine, 10)
    }

    func testNotSignedInCanReadButNotWrite() async throws {
        let store = InMemoryCommunityStore(currentUser: nil)
        await store.seedVotes(pollId: "p", options: ["good", "bad"])
        let status = await store.accountStatus()
        XCTAssertEqual(status, .noAccount)
        XCTAssertFalse(status.canWrite)
        let votes = try await store.fetchVotes(pollId: "p")
        XCTAssertEqual(votes.values.sorted(), ["bad", "good"])
        do {
            try await store.submitVote(pollId: "p", option: "good")
            XCTFail("expected notSignedIn")
        } catch {
            XCTAssertEqual(error as? CommunityError, .notSignedIn)
        }
        let mine = try await store.myVote(pollId: "p")
        XCTAssertNil(mine)
    }
}


/// Half-star listener ratings: new records carry halfStars + rounded stars;
/// legacy records (stars only) read as stars × 2.
final class HalfStarCommunityTests: XCTestCase {
    func testLegacyRecordsReadAsStarsTimesTwo() async throws {
        let store = InMemoryCommunityStore(currentUser: "u")
        await store.seedRatings(movieId: "m", stars: [4, 5])          // older builds
        await store.seedHalfStarRatings(movieId: "m", halfStars: [7])  // new build, 3.5
        let ratings = try await store.fetchRatings(movieId: "m")
        XCTAssertEqual(ratings.values.sorted(), [7, 8, 10])
        let agg = RatingAggregate.from(halfStars: ratings.values)
        XCTAssertEqual(agg.count, 3)
        XCTAssertEqual(agg.average!, 25.0 / 6, accuracy: 1e-12)   // 4.1666…
        XCTAssertEqual(agg.averageToHalf, 4.0)
        XCTAssertEqual(agg.averageHalfStars, 8)
    }

    func testNewRecordsAlsoWriteRoundedStars() async throws {
        let store = InMemoryCommunityStore(currentUser: "u")
        let name = try await store.submitRating(movieId: "m", halfStars: 7)
        let record = await store.record(named: name)
        XCTAssertEqual(record?.halfStars, 7)
        XCTAssertEqual(record?.stars, 4, "older builds see 3.5 rounded to 4")
        let mine = try await store.myRating(movieId: "m")
        XCTAssertEqual(mine, 7)
    }

    func testHalfStarRangeValidated() async {
        let store = InMemoryCommunityStore(currentUser: "u")
        for bad in [0, 11, -1] {
            do { _ = try await store.submitRating(movieId: "m", halfStars: bad); XCTFail("\(bad) accepted") }
            catch { XCTAssertEqual(error as? CommunityError, .invalidStars) }
        }
    }

    func testAggregateAverageHalfPrecision() {
        let a = RatingAggregate.from(halfStars: [9, 8, 9, 8, 0, 11])   // 4.25
        XCTAssertEqual(a.count, 4)
        XCTAssertEqual(a.average!, 4.25, accuracy: 1e-12)
        XCTAssertEqual(a.averageToHalf, 4.5)
        XCTAssertEqual(a.histogram, [0, 0, 0, 2, 2])
        XCTAssertEqual(RatingAggregate.from(stars: [5, 4]).average!, 4.5, accuracy: 1e-12)
    }

    func testSuggestionNeedsICloud() async throws {
        let signedOut = InMemoryCommunityStore(currentUser: nil)
        do { try await signedOut.submitSuggestion(InAppSuggestion(title: "Tremors"), appVersion: "1"); XCTFail() }
        catch { XCTAssertEqual(error as? CommunityError, .notSignedIn) }
        let store = InMemoryCommunityStore(currentUser: "u")
        try await store.submitSuggestion(InAppSuggestion(title: "Tremors"), appVersion: "1")
        let saved = await store.suggestions
        XCTAssertEqual(saved.map(\.title), ["Tremors"])
    }
}

// MARK: - 1.0.1 bulk listener ratings (no CloudKit: in-memory + scripted stores)

/// Scripted `CommunityStore` for the bulk read: returns `bulk` or throws `error`,
/// and counts calls. Everything else is unused here.
private actor ScriptedRatingsStore: CommunityStore {
    var bulk: [String: ListenerRatingEntry] = [:]
    var error: Error?
    private(set) var bulkCalls = 0
    private(set) var requestedIds: [[String]] = []

    init(bulk: [String: ListenerRatingEntry] = [:], error: Error? = nil) {
        self.bulk = bulk
        self.error = error
    }

    func fetchAllRatings(movieIds: [String]) async throws -> [String: ListenerRatingEntry] {
        bulkCalls += 1
        requestedIds.append(movieIds)
        if let error { throw error }
        return bulk
    }

    func accountStatus() async -> CommunityAccountStatus { .noAccount }
    func submitVote(pollId: String, option: String) async throws -> String { throw CommunityError.notSignedIn }
    func fetchVotes(pollId: String) async throws -> [String: String] { [:] }
    func myVote(pollId: String) async throws -> String? { nil }
    func submitRating(movieId: String, halfStars: Int) async throws -> String { throw CommunityError.notSignedIn }
    func fetchRatings(movieId: String) async throws -> [String: Int] {
        bulk.filter { $0.value.movieId == movieId }.mapValues(\.halfStars)
    }
    func myRating(movieId: String) async throws -> Int? { nil }
    func submitSuggestion(_ suggestion: InAppSuggestion, appVersion: String) async throws { throw CommunityError.notSignedIn }
}

final class ListenerRatingsSyncTests: XCTestCase {
    private func entry(_ movie: String, _ half: Int) -> ListenerRatingEntry {
        ListenerRatingEntry(movieId: movie, halfStars: half)
    }

    func testAggregationFromRawRecords() {
        let records = [
            "r1": entry("the-room", 1), "r2": entry("the-room", 2), "r3": entry("the-room", 3),
            "r4": entry("jaws", 10), "r5": entry("jaws", 9),
            "r6": entry("not-requested", 5),
        ]
        let out = ListenerRatingsSync.aggregates(records: records, movieIds: ["the-room", "jaws", "unrated"])
        XCTAssertEqual(Set(out.keys), ["the-room", "jaws", "unrated"])
        XCTAssertEqual(out["the-room"], RatingAggregate.from(halfStars: [1, 2, 3]))
        XCTAssertEqual(out["the-room"]?.average, 1)
        XCTAssertEqual(out["jaws"]?.average, 4.75)
        XCTAssertEqual(out["jaws"]?.count, 2)
        XCTAssertEqual(out["unrated"], RatingAggregate.from(halfStars: []))
        XCTAssertNil(out["unrated"]?.average)
        XCTAssertNil(out["not-requested"])
    }

    func testOwnRecordIsMergedByRecordNameLikeThePerMoviePath() {
        let records = ["mine": entry("m", 2), "other": entry("m", 8)]
        // Re-rated locally: replaces the stale server copy (same record name), never double-counts.
        let replaced = ListenerRatingsSync.aggregates(records: records, own: ["mine": entry("m", 10)], movieIds: ["m"])
        XCTAssertEqual(replaced["m"], RatingAggregate.from(halfStars: CommunityMerge.merging(["mine": 2, "other": 8], own: ("mine", 10)).values))
        XCTAssertEqual(replaced["m"]?.count, 2)
        XCTAssertEqual(replaced["m"]?.average, 4.5)
        // Just saved, not yet visible to the query: added.
        let added = ListenerRatingsSync.aggregates(records: ["other": entry("m", 8)], own: ["mine": entry("m", 4)], movieIds: ["m"])
        XCTAssertEqual(added["m"]?.count, 2)
        XCTAssertEqual(added["m"]?.average, 3)
    }

    func testBulkMatchesPerMoviePathOnTheSameStore() async throws {
        let store = InMemoryCommunityStore(currentUser: nil)
        await store.seedRatings(movieId: "legacy", stars: [1, 2, 5])          // old builds: stars × 2
        await store.seedHalfStarRatings(movieId: "half", halfStars: [1, 4, 7, 10])
        await store.seedHalfStarRatings(movieId: "elsewhere", halfStars: [3])
        let ids = ["legacy", "half", "none"]
        let bulk = try await ListenerRatingsSync.fetchAggregates(store: store, movieIds: ids + ["half"])
        XCTAssertEqual(Set(bulk.keys), Set(ids))
        for id in ids {
            let perMovie = RatingAggregate.from(halfStars: try await store.fetchRatings(movieId: id).values)
            XCTAssertEqual(bulk[id], perMovie, id)
        }
        XCTAssertEqual(bulk["legacy"]?.average, 8.0 / 3.0)
    }

    func testFetchSkipsStoreForNoMoviesAndDedupesIds() async throws {
        let store = ScriptedRatingsStore(bulk: ["r": entry("a", 6)])
        let none = try await ListenerRatingsSync.fetchAggregates(store: store, movieIds: [])
        XCTAssertTrue(none.isEmpty)
        let calls0 = await store.bulkCalls
        XCTAssertEqual(calls0, 0)
        _ = try await ListenerRatingsSync.fetchAggregates(store: store, movieIds: ["b", "a", "a"])
        let requested = await store.requestedIds
        XCTAssertEqual(requested, [["a", "b"]])
    }

    func testFailureFallsBackToCachedAggregates() async {
        let cached = ["a": RatingAggregate.from(halfStars: [2]), "b": RatingAggregate.from(halfStars: [9])]
        let store = ScriptedRatingsStore(error: CommunityError.offline)
        var fetched: [String: RatingAggregate]?
        do {
            fetched = try await ListenerRatingsSync.fetchAggregates(store: store, movieIds: ["a", "b"])
            XCTFail("expected the store error")
        } catch {
            XCTAssertEqual(error as? CommunityError, .offline)
        }
        XCTAssertEqual(ListenerRatingsSync.applying(fetched, to: cached), cached)
        // And the cache keeps feeding the jackpot weighting.
        let snapshot = ListenerRatingsSnapshot(aggregates: ListenerRatingsSync.applying(fetched, to: cached))
        XCTAssertEqual(snapshot.averages, ["a": 1, "b": 4.5])
    }

    func testApplyingUpdatesButKeepsNewerPerMovieData() {
        let current = [
            "a": RatingAggregate.from(halfStars: [2]),
            "b": RatingAggregate.from(halfStars: [9]),
            "c": RatingAggregate.from(halfStars: [5]),
        ]
        let fetched = ["a": RatingAggregate.from(halfStars: [4, 6]), "b": RatingAggregate.from(halfStars: [1])]
        let out = ListenerRatingsSync.applying(fetched, to: current, skipping: ["b"])
        XCTAssertEqual(out["a"], fetched["a"])
        XCTAssertEqual(out["b"], current["b"], "per-movie data newer than the bulk read wins")
        XCTAssertEqual(out["c"], current["c"], "movies missing from the bulk result keep their value")
    }

    func testSnapshotEncodeDecodeRoundTrip() throws {
        let aggregates = [
            "a": RatingAggregate.from(halfStars: [1, 2, 10]),
            "b": RatingAggregate.from(halfStars: []),
        ]
        let date = Date(timeIntervalSince1970: 1_792_000_000)
        let snapshot = ListenerRatingsSnapshot(aggregates: aggregates, updatedAt: date)
        let data = try XCTUnwrap(snapshot.encoded())
        let decoded = try XCTUnwrap(ListenerRatingsSnapshot.decode(data))
        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.aggregates, aggregates)
        XCTAssertEqual(decoded.averages, ["a": 13.0 / 6.0])
        XCTAssertEqual(decoded.updatedAt, date)
    }

    func testSnapshotRejectsGarbageAndBadEntries() throws {
        XCTAssertNil(ListenerRatingsSnapshot.decode(Data("not json".utf8)))
        XCTAssertNil(ListenerRatingsSnapshot.decode(Data(#"{"version":99,"updatedAt":0,"movies":{}}"#.utf8)))
        let json = #"""
        {"version":1,"updatedAt":0,"movies":{
          "ok":{"count":2,"average":3,"histogram":[0,0,2,0,0]},
          "nan":{"count":1,"average":9,"histogram":[0,0,0,0,1]},
          "badHist":{"count":2,"average":3,"histogram":[1,1]},
          "negative":{"count":-1,"histogram":[0,0,0,0,0]},
          "empty":{"count":0,"histogram":[0,0,0,0,0]}
        }}
        """#
        let snapshot = try XCTUnwrap(ListenerRatingsSnapshot.decode(Data(json.utf8)))
        XCTAssertEqual(Set(snapshot.aggregates.keys), ["ok", "empty"])
        XCTAssertEqual(snapshot.averages, ["ok": 3])
    }

    func testSnapshotUserDefaultsPersistence() throws {
        let suite = "mrt-tests-listener-snapshot-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertNil(ListenerRatingsSnapshot.load(from: defaults), "no cache yet")
        let snapshot = ListenerRatingsSnapshot(aggregates: ["a": RatingAggregate.from(halfStars: [3])])
        snapshot.save(to: defaults)
        XCTAssertEqual(ListenerRatingsSnapshot.load(from: defaults)?.averages, ["a": 1.5])
        defaults.set(Data("corrupt".utf8), forKey: ListenerRatingsSnapshot.defaultsKey)
        XCTAssertNil(ListenerRatingsSnapshot.load(from: defaults), "corrupt cache reads as no cache")
    }

    func testCachedAveragesDriveTheJackpotWeighting() throws {
        let snapshot = ListenerRatingsSnapshot(aggregates: [
            "low": RatingAggregate.from(halfStars: [2]),   // 1 star
            "high": RatingAggregate.from(halfStars: [10]), // 5 stars
        ])
        let decoded = try XCTUnwrap(ListenerRatingsSnapshot.decode(try XCTUnwrap(snapshot.encoded())))
        let movies = ["low", "high", "unrated"].map { Movie(id: $0, title: $0, year: 2000, genre: "G") }
        XCTAssertEqual(InfamousSelection.weights(for: movies, averages: decoded.averages), [4.5, 0.5, 2.5])
    }
}
