import XCTest
@testable import MovieRouletteTuesday

/// Edge cases found in the stability audit: empty inputs, zero votes,
/// corrupted files, duplicate ids, and the spin-history cap.
final class StabilityTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mrt-stability-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: Empty inputs

    func testEmptyWheelNeverTraps() {
        let empty = WheelGeometry(weights: [])
        XCTAssertEqual(empty.count, 1)
        XCTAssertEqual(empty.segmentIndex(forRotation: 123), 0)
        XCTAssertEqual(WheelGeometry(segmentCount: 0).count, 1)
        XCTAssertEqual(WheelGeometry(segmentCount: -3).count, 1)
        XCTAssertEqual(WheelGeometry(categories: []).count, 1)
        XCTAssertEqual(WheelMath.segmentIndex(forRotation: 45, segmentCount: 0), 0)
        XCTAssertEqual(WheelMath.segmentIndex(forRotation: .nan, segmentCount: 10), 0)
        XCTAssertEqual(WheelMath.segmentIndex(forRotation: .infinity, segmentCount: 10), 0)
        XCTAssertEqual(WheelGeometry(weights: [1, 2]).segmentIndex(forRotation: .nan), 0)
        var rng = SeededRandomNumberGenerator(seed: 7)
        let target = empty.randomTargetRotation(from: 0, using: &rng)
        XCTAssertTrue(target.isFinite)
        // Valid input is unchanged by the hardening.
        XCTAssertEqual(WheelGeometry(segmentCount: 10).count, 10)
    }

    func testEmptyCatalogIsSafeEverywhere() {
        let catalog = MovieCatalog(categories: [], movies: [])
        let category = RouletteCategory(id: "x", name: "X", colorHex: "#000000")
        var rng = SeededRandomNumberGenerator(seed: 1)
        XCTAssertNil(MovieSelector().selectMovie(from: category, in: catalog, history: [], using: &rng))
        XCTAssertNil(SpinOfTheDay.pick(for: Date(), in: catalog))
        let snap = StatsCalculator.snapshot(history: [], catalog: catalog)
        XCTAssertEqual(snap.totalSpins, 0)
        XCTAssertNil(snap.mostSpunMovie)
        XCTAssertTrue(snap.recent.isEmpty)
        XCTAssertEqual(StatsCalculator.snapshot(history: [], catalog: nil, recentLimit: -5).recent, [])
        XCTAssertEqual(SpinStats(history: []).distinctMoviesSpun, 0)
        XCTAssertEqual(MovieListFilter.notSpunYet.apply(to: [], ratings: PersonalRatings(), spinStats: SpinStats(history: [])), [])
    }

    // MARK: Zero votes

    func testZeroVotesNeverDivideByZero() {
        let poll = PollDefinition(id: "p", episodeGuid: "g", question: "Q?", options: [
            PollOption(id: "a", label: "A"), PollOption(id: "b", label: "B"),
        ])
        let results = PollResults.tally(poll: poll, votes: [String]())
        XCTAssertEqual(results.total, 0)
        XCTAssertTrue(results.rows.allSatisfy { $0.fraction == 0 && $0.fraction.isFinite })
        XCTAssertEqual(results.leaders, [])
        // Votes only for unknown options also count as zero.
        XCTAssertEqual(PollResults.tally(poll: poll, votes: ["zzz"]).total, 0)
        let noOptions = PollDefinition(id: "p2", episodeGuid: "g", question: "Q?", options: [])
        XCTAssertEqual(PollResults.tally(poll: noOptions, votes: ["a"]).rows, [])

        let agg = RatingAggregate.from(stars: [Int]())
        XCTAssertEqual(agg.count, 0)
        XCTAssertNil(agg.average)
        XCTAssertEqual(RatingAggregate.from(stars: [0, 9, -1]).count, 0)
        XCTAssertNil(PersonalRatingsSummary(ratings: PersonalRatings(), catalog: nil).averageStars)
    }

    // MARK: Duplicate ids

    func testDuplicateEpisodeGuidsAreDroppedNotFatal() throws {
        let a = PodcastEpisode(guid: "g1", title: "First")
        let b = PodcastEpisode(guid: "g1", title: "Duplicate")
        let c = PodcastEpisode(guid: "g2", title: "Second")
        XCTAssertEqual(PodcastEpisode.uniqued([a, b, c]).map(\.title), ["First", "Second"])
        let map = PodcastEpisode.byGUID([a, b, c])
        XCTAssertEqual(map.count, 2)
        XCTAssertEqual(map["g1"]?.title, "First")

        let xml = """
        <rss><channel><title>Show</title>
        <item><title>One</title><guid>dup</guid></item>
        <item><title>Two</title><guid>dup</guid></item>
        <item><title>Three</title><guid>other</guid></item>
        </channel></rss>
        """
        let feed = try RSSFeedParser.parse(string: xml)
        XCTAssertEqual(feed.episodes.map(\.title), ["One", "Three"])
    }

    func testDuplicateMovieAndCategoryIdsAreDeduplicated() {
        let catalog = MovieCatalog(
            categories: [
                RouletteCategory(id: "c", name: "C", colorHex: "#111111"),
                RouletteCategory(id: "c", name: "C again", colorHex: "#222222"),
            ],
            movies: [
                Movie(id: "m", title: "Kept", year: 2000, genre: "Drama", categories: ["c"]),
                Movie(id: "m", title: "Dropped", year: 2001, genre: "Drama", categories: ["c"]),
            ]
        )
        let clean = catalog.deduplicated()
        XCTAssertEqual(clean.movies.map(\.title), ["Kept"])
        XCTAssertEqual(clean.categories.map(\.name), ["C"])
        XCTAssertEqual(WheelGeometry(categories: clean.categories).count, 1)
    }

    // MARK: Malformed input

    func testMalformedFeedThrowsInsteadOfCrashing() {
        XCTAssertThrowsError(try RSSFeedParser.parse(data: Data()))
        // Truncated documents: Apple's parser throws; others may not. Either
        // way there's no crash and no half-parsed episode.
        if let feed = try? RSSFeedParser.parse(string: "<rss><channel><item><title>Half") {
            XCTAssertTrue(feed.episodes.isEmpty)
        }
        // Some XML parsers accept bare text; either way: no crash, no episodes.
        if let feed = try? RSSFeedParser.parse(string: "not xml at all") {
            XCTAssertTrue(feed.episodes.isEmpty)
        }
    }

    func testPubDateVariantsParseAndGarbageIsNil() throws {
        XCTAssertNotNil(RSSFeedParser.parseDate("Tue, 07 Jul 2026 05:00:00 -0400"))
        XCTAssertNotNil(RSSFeedParser.parseDate("Tue, 07 Jul 2026 09:00:00 GMT"))
        XCTAssertNotNil(RSSFeedParser.parseDate("07 Jul 2026 09:00:00 +0000"))
        XCTAssertNotNil(RSSFeedParser.parseDate("  Tue, 07 Jul 2026 09:00 +0000\n"))
        XCTAssertEqual(
            RSSFeedParser.parseDate("Tue, 07 Jul 2026 05:00:00 -0400"),
            RSSFeedParser.parseDate("Tue, 07 Jul 2026 09:00:00 GMT")
        )
        XCTAssertNil(RSSFeedParser.parseDate(""))
        XCTAssertNil(RSSFeedParser.parseDate("next tuesday"))
        let feed = try RSSFeedParser.parse(string:
            "<rss><channel><item><title>T</title><guid>g</guid><pubDate>soon</pubDate></item></channel></rss>")
        XCTAssertEqual(feed.episodes.count, 1)
        XCTAssertNil(feed.episodes.first?.pubDate)
    }

    // MARK: Corrupted files

    func testCorruptedHistoryFileThrowsAndIsQuarantined() throws {
        let url = tempDir.appendingPathComponent("spin-history.json")
        try Data("{ not json".utf8).write(to: url)
        let store = SpinHistoryFileStore(fileURL: url)
        XCTAssertThrowsError(try store.loadLog())

        let backup = try XCTUnwrap(CorruptFileQuarantine.quarantine(url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "original moved aside")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertTrue(backup.lastPathComponent.hasPrefix("spin-history.corrupt-"))
        XCTAssertEqual(try Data(contentsOf: backup), Data("{ not json".utf8), "backup keeps the bytes")
        XCTAssertEqual(try store.loadLog(), SpinHistoryLog(), "starts fresh")
        XCTAssertNil(CorruptFileQuarantine.quarantine(url), "nothing to move")
    }

    func testQuarantineKeepsOnlyNewestBackups() throws {
        let url = tempDir.appendingPathComponent("personal-ratings.json")
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for i in 0..<5 {
            try Data("bad \(i)".utf8).write(to: url)
            XCTAssertNotNil(CorruptFileQuarantine.quarantine(url, now: start.addingTimeInterval(Double(i) * 60)))
        }
        let backups = CorruptFileQuarantine.backups(for: url)
        XCTAssertEqual(backups.count, CorruptFileQuarantine.keepBackups)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(backups.last)), Data("bad 4".utf8))
    }

    func testPersonalRatingsDecodingIsTolerant() throws {
        let json = """
        {"entries":{
          "a":{"rating":9,"status":"watched","updatedAt":0},
          "b":{"rating":3,"status":"somethingNew"},
          "c":{"rating":"five","status":"wantToWatch"},
          "d":{"status":"bogus"}
        }}
        """
        let url = tempDir.appendingPathComponent("personal-ratings.json")
        try Data(json.utf8).write(to: url)
        let ratings = try PersonalRatingsFileStore(fileURL: url).load()
        XCTAssertEqual(ratings.rating(for: "a"), 5, "clamped")
        XCTAssertEqual(ratings.status(for: "a"), .watched)
        XCTAssertEqual(ratings.rating(for: "b"), 3)
        XCTAssertNil(ratings.status(for: "b"), "unknown status ignored")
        XCTAssertEqual(ratings.status(for: "c"), .wantToWatch)
        XCTAssertNil(ratings.rating(for: "c"))
        XCTAssertNil(ratings.entry(for: "d"), "nothing usable -> dropped")
        // Garbage still throws (the store then quarantines it).
        try Data("[1,2".utf8).write(to: url)
        XCTAssertThrowsError(try PersonalRatingsFileStore(fileURL: url).load())
    }

    func testLegacyHistoryArrayStillLoadsAndBadEntriesAreSkipped() throws {
        let url = tempDir.appendingPathComponent("spin-history.json")
        let good = SpinResult(movieId: "m1", categoryId: "c1", timestamp: Date(timeIntervalSinceReferenceDate: 100))
        let legacy = try JSONEncoder().encode([good])
        try legacy.write(to: url)
        let store = SpinHistoryFileStore(fileURL: url)
        XCTAssertEqual(try store.loadLog().results, [good])
        XCTAssertEqual(try store.load(), [good])

        // One malformed entry doesn't wipe the rest.
        var array = try XCTUnwrap(JSONSerialization.jsonObject(with: legacy) as? [Any])
        array.append(["movieId": 42])
        try JSONSerialization.data(withJSONObject: array).write(to: url)
        XCTAssertEqual(try store.loadLog().results, [good])

        // v2 object with a missing archive.
        try Data(#"{"version":2,"results":[]}"#.utf8).write(to: url)
        XCTAssertEqual(try store.loadLog(), SpinHistoryLog())
    }

    // MARK: History cap

    func testHistoryCapCompactsButKeepsCounts() throws {
        var log = SpinHistoryLog()
        for i in 0..<1_200 {
            log.append(SpinResult(movieId: "m\(i % 7)", categoryId: "c\(i % 3)"), detailLimit: 500)
        }
        XCTAssertEqual(log.results.count, 500)
        XCTAssertEqual(log.totalSpins, 1_200)
        XCTAssertEqual(log.archive.totalSpins, 700)

        let stats = log.stats
        XCTAssertEqual(stats.totalSpins, 1_200)
        XCTAssertEqual((0..<7).map { stats.spinCount(forMovie: "m\($0)") }.reduce(0, +), 1_200)
        XCTAssertEqual(stats.spinCount(forMovie: "m0"), 172)  // ceil(1200 / 7)
        XCTAssertEqual(stats.spinCount(forCategory: "c0"), 400)
        XCTAssertEqual(stats.distinctMoviesSpun, 7)

        // Stats tab totals include archived spins.
        let catalog = MovieCatalog(categories: [], movies: [Movie(id: "m0", title: "Zero", year: 2000, genre: "Horror")])
        let snap = StatsCalculator.snapshot(history: log.results, catalog: catalog, archive: log.archive)
        XCTAssertEqual(snap.totalSpins, 1_200)
        XCTAssertEqual(snap.genreBreakdown.first, CountedGenre(genre: "Horror", count: 172))
        XCTAssertEqual(snap.recent.count, 10)

        // Round-trips through the file store.
        let store = SpinHistoryFileStore(fileURL: tempDir.appendingPathComponent("spin-history.json"))
        try store.saveLog(log)
        XCTAssertEqual(try store.loadLog(), log)

        // Compacting an oversized legacy log on load.
        var big = SpinHistoryLog(results: (0..<50).map { _ in SpinResult(movieId: "x", categoryId: "y") })
        big.compact(detailLimit: 10)
        XCTAssertEqual(big.results.count, 10)
        XCTAssertEqual(big.stats.spinCount(forMovie: "x"), 50)
        big.compact(detailLimit: -1)
        XCTAssertEqual(big.results.count, 0)
        XCTAssertEqual(big.totalSpins, 50)
    }

    // MARK: Caches and back-off

    func testTimedCacheIsBounded() {
        var cache = TimedCache<String, Int>(ttl: 60, maxEntries: 3)
        let t0 = Date(timeIntervalSince1970: 0)
        for i in 0..<10 { cache.insert(i, for: "k\(i)", now: t0.addingTimeInterval(Double(i))) }
        XCTAssertEqual(cache.count, 3)
        XCTAssertNil(cache.staleValue(for: "k0"), "oldest evicted")
        XCTAssertEqual(cache.staleValue(for: "k9"), 9)
    }

    func testRateLimitBackoffIsBoundedAndNeverLoops() {
        var backoff = CommunityBackoff()
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(backoff.isBlocked(now: now))
        backoff.note(CommunityError.offline, now: now)
        XCTAssertFalse(backoff.isBlocked(now: now), "offline doesn't block; the user can just retry")
        backoff.note(CommunityError.busy(retryAfter: 5), now: now)
        XCTAssertTrue(backoff.isBlocked(now: now.addingTimeInterval(4)))
        XCTAssertEqual(backoff.secondsRemaining(now: now.addingTimeInterval(1.5)), 4)
        XCTAssertFalse(backoff.isBlocked(now: now.addingTimeInterval(5)))
        backoff.note(CommunityError.busy(retryAfter: 100_000), now: now)
        XCTAssertFalse(backoff.isBlocked(now: now.addingTimeInterval(301)), "capped at 5 minutes")
        backoff.reset()
        XCTAssertFalse(backoff.isBlocked(now: now))
        for error in [CommunityError.offline, .busy(retryAfter: nil), .busy(retryAfter: 1), .quotaExceeded, .notSetUp] {
            XCTAssertFalse((error.errorDescription ?? "").isEmpty)
        }
        XCTAssertEqual(CommunityError.busy(retryAfter: 1).errorDescription, "iCloud is busy right now. Try again in 1 second.")
    }
}
