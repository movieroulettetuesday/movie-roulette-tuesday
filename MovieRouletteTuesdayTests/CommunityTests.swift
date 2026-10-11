import XCTest
@testable import MovieRouletteTuesday

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

        try await store.submitRating(movieId: "m", stars: 4)
        try await store.submitRating(movieId: "m", stars: 2)
        await store.setCurrentUser("user-1")
        try await store.submitRating(movieId: "m", stars: 5)
        let agg = RatingAggregate.from(stars: try await store.fetchRatings(movieId: "m").values)
        XCTAssertEqual(agg.count, 2)
        XCTAssertEqual(agg.average!, 3.5, accuracy: 1e-12)
        let mine = try await store.myRating(movieId: "m")
        XCTAssertEqual(mine, 5)
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
