import XCTest
@testable import MovieRouletteTuesday

/// The search model with a STUBBED parser (no Foundation Model): gating,
/// debounce outcome, timeouts, the list switch with handoff and bounce
/// prevention, chip removal, and all 32 shared cases end to end.
@MainActor
final class NLSearchModelTests: XCTestCase {
    final class CountingParser: NLSearchParsing, @unchecked Sendable {
        private let lock = NSLock()
        private var _calls = 0
        private let result: Result<NLSearchFilter, Error>
        private let delay: Duration?
        init(_ result: Result<NLSearchFilter, Error>, delay: Duration? = nil) { self.result = result; self.delay = delay }
        var calls: Int { lock.withLock { _calls } }
        func parse(_ question: String) async throws -> NLSearchFilter {
            lock.withLock { _calls += 1 }
            if let delay { try await Task.sleep(for: delay) }
            return try result.get()
        }
    }

    private var catalog: MovieCatalog!
    private var switches: [NLSearch.List] = []

    override func setUp() async throws {
        catalog = NLSearchFixture.catalog()
        switches = []
    }

    private func model(_ parser: (any NLSearchParsing)?, status: SuggestionModelStatus = .available) -> NLSearchModel {
        NLSearchModel(availability: { status }, makeParser: { parser })
    }

    private func run(_ m: NLSearchModel, _ list: NLSearch.List, _ query: String) async -> NLSearchModel.Outcome {
        m[list].query = query
        m.queryChanged(list, titles: catalog.movies.map(\.title))
        return await m.parse(list, catalog: catalog) { switches.append($0) }
    }

    func testUnavailableModelSkipsParseAndKeepsKeywordSearch() async {
        for status in [SuggestionModelStatus.unavailable, .temporarilyUnavailable] {
            let parser = CountingParser(.success(.init(genre: "Horror")))
            let m = model(parser, status: status)
            let outcome = await run(m, .movies, "free 80s horror I haven't watched")
            XCTAssertEqual(outcome, .keyword, "\(status)")
            XCTAssertEqual(parser.calls, 0)
            XCTAssertNil(m.movies.filter)
            XCTAssertFalse(m.isEnabled)
        }
        XCTAssertEqual(switches, [])
    }

    func testNoParserIsKeywordSearch() async {
        let m = model(nil)
        let outcome = await run(m, .movies, "free horror")
        XCTAssertEqual(outcome, .keyword)
        XCTAssertNil(m.movies.filter)
    }

    func testAvailabilityOverrideAndDefaultsBelowIOS26() {
        NLSearchAvailability.override = .unavailable
        XCTAssertEqual(NLSearchAvailability.current(), .unavailable)
        NLSearchAvailability.override = .available
        XCTAssertEqual(NLSearchAvailability.current(), .available)
        NLSearchAvailability.override = nil
    }

    func testTitleLikeQueryNeverCallsTheModel() async {
        let parser = CountingParser(.success(.init(title: "x")))
        let m = model(parser)
        for q in ["the thing", "Shudder", "???"] {
            let outcome = await run(m, .movies, q)
            XCTAssertEqual(outcome, .keyword, q)
        }
        XCTAssertEqual(parser.calls, 0)
    }

    func testQuestionOnCurrentListShowsChips() async {
        let m = model(CountingParser(.success(.init(genre: "Horror", freeOnly: true))))
        let outcome = await run(m, .episodes, "free horror")
        XCTAssertEqual(outcome, .chips)
        XCTAssertEqual(m.episodes.filter, .init(genre: "Horror", freeOnly: true))
        XCTAssertEqual(m.chips(.episodes, catalog: catalog).map(\.label), ["Horror", "Free"])
        XCTAssertEqual(m.episodes.resetToken, 0)
        XCTAssertEqual(switches, [])
    }

    func testEpisodeKindOnMoviesHandsOffAndClearsMovies() async {
        let m = model(CountingParser(.success(.init(title: "The Thing", kind: .episode))))
        let q = "episodes about The Thing"
        m.movies.searchPresented = true
        let outcome = await run(m, .movies, q)
        XCTAssertEqual(outcome, .switched(.episodes))
        XCTAssertEqual(switches, [.episodes])
        XCTAssertEqual(m.episodes.query, q)
        XCTAssertEqual(m.episodes.filter?.title, "The Thing")
        XCTAssertEqual(m.episodes.parsedQuery, q)
        XCTAssertEqual(m.episodes.resetToken, 1, "destination opens at its root / detail resets")
        XCTAssertEqual(m.movies.query, "")
        XCTAssertNil(m.movies.filter)
        XCTAssertFalse(m.movies.searchPresented, "source search dismissed")
        XCTAssertFalse(m.episodes.searchPresented, "destination keyboard not forced open")
        // Going back to Movies does not bounce forward again.
        let back = await m.parse(.movies, catalog: catalog) { switches.append($0) }
        XCTAssertEqual(back, .keyword)
        // The destination's own debounce (on appear) does not re-parse.
        let again = await m.parse(.episodes, catalog: catalog) { switches.append($0) }
        XCTAssertEqual(again, .skipped)
        XCTAssertEqual(switches, [.episodes])
    }

    func testMovieKindOnEpisodesHandsOffTheOtherWay() async {
        let m = model(CountingParser(.success(.init(kind: .movie, watched: .unwatched))))
        let outcome = await run(m, .episodes, "show me movies I haven't watched")
        XCTAssertEqual(outcome, .switched(.movies))
        XCTAssertEqual(switches, [.movies])
        XCTAssertEqual(m.movies.query, "show me movies I haven't watched")
        XCTAssertEqual(m.movies.filter?.watched, .unwatched)
        XCTAssertEqual(m.movies.resetToken, 1)
        XCTAssertEqual(m.episodes.query, "")
        XCTAssertNil(m.episodes.filter)
    }

    func testMovieKindWhileOnMoviesStaysWithoutReset() async {
        let m = model(CountingParser(.success(.init(kind: .movie, provider: "Shudder"))))
        let outcome = await run(m, .movies, "movies on Shudder")
        XCTAssertEqual(outcome, .chips)
        XCTAssertEqual(m.movies.query, "movies on Shudder")
        XCTAssertEqual(m.movies.resetToken, 0)
        XCTAssertEqual(switches, [])
    }

    func testAnyKindStaysPut() async {
        let m = model(CountingParser(.success(.init(title: "The Thing", kind: .any))))
        let outcome = await run(m, .episodes, "find me The Thing")
        XCTAssertEqual(outcome, .chips)
        XCTAssertEqual(switches, [])
    }

    func testFailedEmptyAndTimedOutParsesFallBackWithoutSwitching() async {
        let failing = model(CountingParser(.failure(NLSearchError.noParse)))
        let failed = await run(failing, .movies, "free horror")
        XCTAssertEqual(failed, .keyword)
        XCTAssertNil(failing.movies.filter)

        let empty = model(CountingParser(.success(.init(kind: .any, genre: "Animation"))))
        let emptied = await run(empty, .movies, "animation please find")
        XCTAssertEqual(emptied, .keyword, "validation empties it")

        let slow = model(CountingParser(.success(.init(kind: .episode, season: 4)), delay: .seconds(5)))
        slow.timeout = .milliseconds(50)
        let timedOut = await run(slow, .movies, "season 4")
        XCTAssertEqual(timedOut, .keyword)
        XCTAssertNil(slow.movies.filter)
        XCTAssertEqual(slow.episodes.query, "")
        XCTAssertEqual(switches, [])
    }

    func testTextChangedDuringParseIsDropped() async {
        let parser = CountingParser(.success(.init(kind: .episode, season: 4)), delay: .milliseconds(100))
        let m = model(parser)
        m.movies.query = "season 4"
        let task = Task { await m.parse(.movies, catalog: catalog) { self.switches.append($0) } }
        try? await Task.sleep(for: .milliseconds(20))
        m.movies.query = "season 4 episode"
        let outcome = await task.value
        XCTAssertEqual(outcome, .skipped)
        XCTAssertNil(m.movies.filter)
        XCTAssertEqual(switches, [])
    }

    func testEditingToNonQuestionDropsChipsAtOnce() async {
        let m = model(CountingParser(.success(.init(genre: "Horror", freeOnly: true))))
        _ = await run(m, .movies, "free horror")
        XCTAssertNotNil(m.movies.filter)
        // Still a question: the last good chips stay until the new parse lands.
        m.movies.query = "free horror 80s"
        m.queryChanged(.movies, titles: [])
        XCTAssertNotNil(m.movies.filter)
        m.movies.query = "alien"
        m.queryChanged(.movies, titles: [])
        XCTAssertNil(m.movies.filter)
    }

    func testRemovingChipsReappliesAndLastChipReturnsToKeyword() async {
        let m = model(CountingParser(.success(.init(genre: "Horror", freeOnly: true))))
        _ = await run(m, .movies, "free horror")
        m.removeChip(.free, from: .movies, catalog: catalog)
        XCTAssertEqual(m.movies.filter, .init(genre: "Horror"))
        m.removeChip(.genre, from: .movies, catalog: catalog)
        XCTAssertNil(m.movies.filter)
        // Removal never triggers a re-parse of the same text.
        let again = await m.parse(.movies, catalog: catalog) { switches.append($0) }
        XCTAssertEqual(again, .skipped)
    }

    /// The 32 shared cases through the model with a stub parse, from both lists.
    func testSharedCasesEndToEndFromBothLists() async throws {
        let cases = try NLSearchSharedCasesTests.loadCases()
        XCTAssertEqual(cases.count, 32)
        for c in cases {
            let stub = try NLSearchSharedCasesTests.stubParse(c)
            for start in NLSearch.List.allCases {
                switches = []
                let m = model(StubNLSearchParser([c.question: stub]))
                let outcome = await run(m, start, c.question)
                let expected: NLSearchModel.Outcome
                if c.outcome == "empty-filter" {
                    expected = .keyword
                } else if c.switchesTo == "movies", start == .episodes {
                    expected = .switched(.movies)
                } else if c.switchesTo == "episodes", start == .movies {
                    expected = .switched(.episodes)
                } else {
                    expected = .chips
                }
                XCTAssertEqual(outcome, expected, "\(c.id) from \(start)")
                if case .switched(let to) = expected {
                    XCTAssertEqual(switches, [to], c.id)
                    XCTAssertEqual(m[to].query, c.question, c.id)
                    XCTAssertNotNil(m[to].filter, c.id)
                    XCTAssertEqual(m[start].query, "", c.id)
                } else {
                    XCTAssertEqual(switches, [], c.id)
                }
            }
        }
    }
}
