import XCTest
@testable import MovieRouletteTuesday

/// Gate, prompt, parsing, and fallback. No Apple Intelligence and no network.
@MainActor
final class SuggestionTests: XCTestCase {
    private var catalog: MovieCatalog!
    private var devil: Movie!
    private var thing82: Movie!
    private var plain: Movie!

    override func setUp() {
        super.setUp()
        catalog = Self.makeCatalog()
        devil = catalog.movie(withId: "the-devils-rain-1975")
        thing82 = catalog.movie(withId: "the-thing-1982")
        plain = catalog.movie(withId: "no-stream")
        IntentRuntime.reset()
        IntentRuntime.opensApp = false
        IntentRuntime.catalog = { [catalog] in catalog! }
        SuggestionAvailability.reset()
        SuggestionGenerator.reset()
        AppRouter.shared.pendingURL = nil
        AppRouter.shared.pendingSpin = nil
    }

    override func tearDown() {
        SuggestionAvailability.reset()
        SuggestionGenerator.reset()
        IntentRuntime.reset()
        AppRouter.shared.pendingURL = nil
        AppRouter.shared.pendingSpin = nil
        super.tearDown()
    }

    // MARK: Gate

    func testGateHidesEntryWhenUnavailableAndShowsItWhenAvailableOrNotReady() {
        XCTAssertEqual(SuggestionGate.entry(for: .available), .ready)
        XCTAssertEqual(SuggestionGate.entry(for: .temporarilyUnavailable), .notReady)
        XCTAssertEqual(SuggestionGate.entry(for: .unavailable), .hidden)
        XCTAssertFalse(SuggestionGate.intentOffersSpin(for: .available))
        XCTAssertTrue(SuggestionGate.intentOffersSpin(for: .temporarilyUnavailable))
        XCTAssertTrue(SuggestionGate.intentOffersSpin(for: .unavailable))
    }

    func testAvailabilityOverrideDoesNotNeedTheSystemModel() {
        SuggestionAvailability.override = .unavailable
        XCTAssertEqual(SuggestionAvailability.current(), .unavailable)
        XCTAssertEqual(SuggestionGate.entry(for: SuggestionAvailability.current()), .hidden)

        SuggestionAvailability.override = .temporarilyUnavailable
        XCTAssertEqual(SuggestionGate.entry(for: SuggestionAvailability.current()), .notReady)

        SuggestionAvailability.override = .available
        XCTAssertEqual(SuggestionGate.entry(for: SuggestionAvailability.current()), .ready)
    }

    // MARK: Recent spins

    func testRecentIDsPreferNewestAndCapTheSet() {
        let results = (0..<15).map { i in
            SpinResult(
                movieId: "m-\(i)",
                categoryId: "cat",
                timestamp: Date(timeIntervalSince1970: TimeInterval(i))
            )
        }
        let recent = SuggestionPrompt.recentIDs(from: results, limit: 10)
        XCTAssertEqual(recent.count, 10)
        XCTAssertTrue(recent.contains("m-14"))
        XCTAssertTrue(recent.contains("m-5"))
        XCTAssertFalse(recent.contains("m-4"))
        XCTAssertFalse(recent.contains("m-0"))
    }

    // MARK: Rows from real state

    func testRowsCarryOnlyRealStateAndScore() {
        var ratings = PersonalRatings()
        ratings.setStatus(.wantToWatch, for: devil.id)
        ratings.setHalfStars(7, for: thing82.id)
        let rows = PickMovie.rows(
            catalog: catalog, ratings: ratings, recentIDs: ["the-thing-2011"], services: MyServices(ids: [8])
        )
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        let d = try! XCTUnwrap(byID[devil.id])
        XCTAssertTrue(d.onWatchlist)
        XCTAssertFalse(d.isWatched)
        // Shudder is first in the stream list, but only Netflix is one of "my services".
        XCTAssertEqual(d.serviceProvider, "Netflix")
        XCTAssertNil(d.freeProvider)
        XCTAssertEqual(d.categories, ["Horror", "Cult"])
        XCTAssertEqual(d.score, 5)
        XCTAssertTrue(try! XCTUnwrap(byID[thing82.id]).isWatched, "a rating implies watched")
        XCTAssertTrue(try! XCTUnwrap(byID["the-thing-2011"]).recent)
        XCTAssertEqual(try! XCTUnwrap(byID[plain.id]).score, 0)
    }

    // MARK: Shared cases (mrt-shared/wsiw, byte copies in Fixtures/wsiw)

    static func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/wsiw/\(name)")
    }

    static func sharedJSON(_ name: String) throws -> [String: Any] {
        let data = try Data(contentsOf: fixtureURL(name))
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testBannedPatternsAreTheSharedListExactly() throws {
        let root = try Self.sharedJSON("banned-phrases.json")
        XCTAssertEqual(root["version"] as? Int, 1)
        XCTAssertEqual(try XCTUnwrap(root["patterns"] as? [String]), BannedPhrases.patterns)
    }

    func testSharedComposerCases() throws {
        let cases = try XCTUnwrap(try Self.sharedJSON("wsiw-cases.json")["composer"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 4)
        for c in cases {
            let name = c["name"] as? String ?? "?"
            let movie = Self.composerMovie(c)
            let facts = ReasonComposer.facts(for: movie).map(\.text)
            XCTAssertEqual(facts, c["expectFacts"] as? [String], name)
            for forbidden in c["forbid"] as? [String] ?? [] {
                XCTAssertFalse(facts.contains { $0.contains(forbidden) }, "\(name): \(forbidden)")
            }
        }
    }

    func testSharedValidatorCases() throws {
        let cases = try XCTUnwrap(try Self.sharedJSON("wsiw-cases.json")["validator"] as? [[String: Any]])
        let providers = StreamingCatalog.services(in: catalog.movies).map(\.name)
        XCTAssertEqual(cases.count, 3)
        for c in cases {
            let text = try XCTUnwrap(c["text"] as? String)
            let clean = BannedPhrases.isClean(text, providerNames: providers)
            XCTAssertEqual(clean ? "accept" : "reject", c["expect"] as? String, text)
        }
        // Runtime provider names are banned too, even without another banned word.
        XCTAssertFalse(BannedPhrases.isClean("Big on Shudder.", providerNames: providers))
        XCTAssertTrue(BannedPhrases.isClean("Big, loud fun.", providerNames: providers))
    }

    func testSharedCandidateCases() throws {
        let cases = try XCTUnwrap(try Self.sharedJSON("wsiw-cases.json")["candidates"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 2)
        for c in cases {
            let name = c["name"] as? String ?? "?"
            let movies = try XCTUnwrap(c["movies"] as? [[String: Any]]).map(Self.candidateMovie)
            for seed in 0..<20 as Range<UInt64> {
                var rng = SeededGenerator(seed: seed)
                let picked = PickCandidates.select(movies, using: &rng).map(\.id)
                for excluded in c["expectExcluded"] as? [String] ?? [] {
                    XCTAssertFalse(picked.contains(excluded), "\(name) seed \(seed): \(excluded)")
                }
                if let first = c["expectFirst"] as? String { XCTAssertEqual(picked.first, first, name) }
                if let cap = c["cap"] as? Int { XCTAssertLessThanOrEqual(picked.count, cap) }
                if let exact = c["expectCandidates"] as? [String] { XCTAssertEqual(picked, exact, name) }
            }
        }
    }

    func testSharedPickCases() throws {
        let cases = try XCTUnwrap(try Self.sharedJSON("wsiw-cases.json")["picks"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 3)
        for c in cases {
            let genre = c["genre"] as? String ?? "Drama"
            let n = c["n"] as? Int ?? 12
            let candidates = (1...n).map { i in
                PickMovie(id: "m\(i)", title: "Movie \(i)", year: 1990, genre: genre, categories: [],
                          status: nil, halfStars: nil, recent: false, serviceProvider: nil, freeProvider: nil)
            }
            var raw: RawPick?
            if let model = c["model"] as? [String: Any] {
                raw = RawPick(pick: model["pick"] as? Int ?? 0, vibe: model["vibe"] as? String ?? "")
            }
            let resolution = PickResolver.resolve(raw, candidates: candidates, providerNames: [])
            if let expect = c["expect"] as? String {
                XCTAssertEqual(expect, "templateFallback")
                XCTAssertEqual(resolution, .templateFallback)
            } else {
                let expect = try XCTUnwrap(c["expect"] as? [String: Any])
                XCTAssertEqual(expect["vibe"] as? String, "fromGenre")
                XCTAssertEqual(resolution, .model(pick: expect["pick"] as? Int ?? -1, vibe: .fromGenre(genre), vibeFromGenre: true))
            }
        }
    }

    // MARK: Candidates beyond the shared cases

    func testCandidatesCapAtTwelveRelaxRecentThenRewatchAndEmptyOffersSpin() {
        let many = (0..<30).map { i in Self.movie("m\(i)", onService: i % 2 == 0) }
        var rng = SeededGenerator(seed: 7)
        let picked = PickCandidates.select(many, using: &rng)
        XCTAssertEqual(picked.count, 12)
        XCTAssertTrue(picked.allSatisfy { $0.serviceProvider != nil }, "service titles outrank the rest")

        // Two unwatched, one recent: the recent one is allowed back in.
        let few = [Self.movie("a"), Self.movie("b"), Self.movie("r", recent: true), Self.movie("w", status: .watched, halfStars: 10)]
        var rng2 = SeededGenerator(seed: 1)
        XCTAssertEqual(Set(PickCandidates.select(few, using: &rng2).map(\.id)), ["a", "b", "r"])

        // Watched-only, nothing rated 4 stars: no candidates.
        var rng3 = SeededGenerator(seed: 1)
        XCTAssertTrue(PickCandidates.select([Self.movie("x", status: .watched)], using: &rng3).isEmpty)
    }

    func testTiesShuffleBySeedButScoreOrderHolds() {
        let movies = (0..<12).map { Self.movie("t\($0)") } + [Self.movie("top", status: .wantToWatch)]
        var orders = Set<[String]>()
        for seed in 0..<10 as Range<UInt64> {
            var rng = SeededGenerator(seed: seed)
            let ids = PickCandidates.select(movies, using: &rng).map(\.id)
            XCTAssertEqual(ids.first, "top")
            orders.insert(ids)
        }
        XCTAssertGreaterThan(orders.count, 1, "ties are shuffled per tap")
    }

    // MARK: Prompt

    func testPromptRowsAreExplicitNumberedAndSmall() throws {
        let real = try Self.bundledCatalog()
        let rows = PickMovie.rows(catalog: real, ratings: PersonalRatings(), recentIDs: [], services: MyServices())
        // Worst case: the 12 longest rows in the catalog.
        let longest = Array(rows.sorted { PickPrompt.row(for: $0).count > PickPrompt.row(for: $1).count }.prefix(12))
        let prompt = PickPrompt.prompt(for: longest)
        let lines = prompt.split(separator: "\n")
        XCTAssertEqual(lines.count, 14)
        for (i, line) in lines.dropFirst().dropLast().enumerated() {
            XCTAssertTrue(line.hasPrefix("\(i + 1). "), String(line))
            XCTAssertTrue(line.contains("watchlist: yes") || line.contains("watchlist: no"), String(line))
            XCTAssertTrue(line.contains("on your services: "), String(line))
        }
        // Budget (Android parity, PR #13): about 550 tokens for 12 rows. At ~4
        // characters a token, the worst case must stay under 2,400 characters.
        XCTAssertLessThan(prompt.count + PickPrompt.instructions.count, 2400, "prompt is \(prompt.count) chars")
        XCTAssertFalse(prompt.lowercased().contains("http"))
        XCTAssertFalse(prompt.contains("{"))
        XCTAssertFalse(PickPrompt.instructions.lowercased().contains("rating"))
        XCTAssertFalse(PickPrompt.instructions.lowercased().contains("why"))
    }

    // MARK: Vibes, facts, speech

    func testVibesFollowTheAndroidGenreTableAndClassicIsPre1980() {
        for genre in ["Horror", "Sci-Fi", "Comedy", "Thriller", "Fantasy", "Action", "Romance", "Musical", "Western"] {
            let own = try! XCTUnwrap(PickVibe.fromGenre(genre), genre)
            XCTAssertTrue(own.fits(genre: genre, year: 2000), genre)
        }
        XCTAssertNil(PickVibe.fromGenre("Drama"), "no single safe line for Drama")
        XCTAssertNil(PickVibe.fromGenre("Documentary"))
        XCTAssertFalse(PickVibe.scares.fits(genre: "Comedy", year: 2000))
        XCTAssertTrue(PickVibe.classic.fits(genre: "Drama", year: 1979))
        XCTAssertFalse(PickVibe.classic.fits(genre: "Drama", year: 1980))
        // A mood that doesn't fit is left out when the genre has no default.
        XCTAssertNil(PickVibe.validated(.laughs, genre: "Drama", year: 2001))
        XCTAssertEqual(PickVibe.validated(.laughs, genre: "Horror", year: 2001), .scares)
        XCTAssertEqual(PickVibe.validated(.dark, genre: "Drama", year: 2001), .dark)
        let drama = [PickMovie(id: "d", title: "D", year: 2001, genre: "Drama", categories: [], status: nil, halfStars: nil,
                               recent: false, serviceProvider: nil, freeProvider: nil)]
        XCTAssertEqual(PickResolver.resolve(RawPick(pick: 1, vibe: "laughs"), candidates: drama, providerNames: []),
                       .model(pick: 1, vibe: nil, vibeFromGenre: true))
    }

    func testStrictParseFallsBackOnAnythingButAnExactVibe() {
        let list = [Self.movie("a"), Self.movie("b")]
        for vibe in ["Laughs", " laughs", "funny", "", "Good for a laugh."] {
            XCTAssertEqual(PickResolver.resolve(RawPick(pick: 1, vibe: vibe), candidates: list, providerNames: []), .templateFallback, vibe)
        }
        XCTAssertEqual(PickResolver.resolve(RawPick(pick: 3, vibe: "cult"), candidates: list, providerNames: []), .templateFallback)
        XCTAssertEqual(PickResolver.resolve(RawPick(pick: 2, vibe: "cult"), candidates: list, providerNames: []),
                       .model(pick: 2, vibe: .cult, vibeFromGenre: false))
    }

    func testRatingFactsAndSpokenLine() {
        XCTAssertEqual(PickFact.rated(halfStars: 8).text, "You rated it 4 stars")
        XCTAssertEqual(PickFact.rated(halfStars: 2).text, "You rated it 1 star")
        let movie = PickMovie(id: "x", title: "Christmas Evil", year: 1980, genre: "Horror", categories: ["Horror"],
                              status: .wantToWatch, halfStars: nil, recent: false, serviceProvider: "Netflix", freeProvider: nil)
        let accepted = AcceptedSuggestion(movie: movie, lead: PickVibe.scares.line, isFallback: false)
        XCTAssertEqual(accepted.spoken, "Try Christmas Evil (1980). Good for a scare. It’s on your watchlist and streaming on Netflix.")
        let rewatch = PickMovie(id: "y", title: "Alien", year: 1979, genre: "Sci-Fi", categories: [],
                                status: .watched, halfStars: 9, recent: false, serviceProvider: nil, freeProvider: "Tubi")
        XCTAssertEqual(AcceptedSuggestion(movie: rewatch, lead: nil, isFallback: true).spoken,
                       "Try Alien (1979). You rated it 4.5 stars. It’s free on Tubi.")
        XCTAssertEqual(accepted.factsLine, "On your watchlist · Not watched yet · Streaming on Netflix · From the Horror category")
    }

    func testFallbackLeadIsTrueForTheMovie() {
        XCTAssertEqual(ReasonComposer.fallbackLead(for: Self.movie("a", status: .wantToWatch)), "Picked from your watchlist and services.")
        XCTAssertEqual(ReasonComposer.fallbackLead(for: Self.movie("b", onService: true)), "Picked from your watchlist and services.")
        // Only when it's true for that movie; otherwise the card shows facts only.
        XCTAssertNil(ReasonComposer.fallbackLead(for: Self.movie("c")))
        XCTAssertNil(ReasonComposer.fallbackLead(for: Self.movie("d", free: true)))
        XCTAssertNil(ReasonComposer.fallbackLead(for: Self.movie("e", status: .watched, halfStars: 9)))
    }

    // MARK: Generator

    func testGeneratorOffersSpinWhenUnavailableAndDoesNotCallTheSessionOrSpin() async {
        SuggestionAvailability.override = .unavailable
        let counter = CallCounter()
        SuggestionGenerator.responder = { StubSession(answers: [], counter: counter) }
        let history = SpinHistoryStore(fileStore: nil)
        IntentRuntime.history = { history }

        let outcome = await SuggestionGenerator.generate()
        XCTAssertEqual(outcome, .offerSpin(.unavailable))
        XCTAssertEqual(counter.picks, 0, "the model must not be asked when the gate is closed")
        XCTAssertTrue(history.results.isEmpty)
        XCTAssertNil(AppRouter.shared.pendingSpin)

        let intent = WhatShouldIWatchIntent()
        _ = try? await intent.perform()
        XCTAssertTrue(history.results.isEmpty)
        XCTAssertNil(AppRouter.shared.pendingSpin)
        XCTAssertNil(AppRouter.shared.pendingURL)
    }

    func testGeneratorSaysNotReadyWithoutCallingTheSession() async {
        SuggestionAvailability.override = .temporarilyUnavailable
        let counter = CallCounter()
        SuggestionGenerator.responder = { StubSession(answers: [], counter: counter) }
        let notReady = await SuggestionGenerator.generate()
        XCTAssertEqual(notReady, .notReady)
        XCTAssertEqual(counter.picks, 0)
    }

    /// Matthew's 1.1 (15) report: the reason claimed a watchlist entry and a
    /// rating that didn't exist. The model's words never reach the card now.
    func testModelCannotClaimAWatchlistOrRatingThatDoesNotExist() async throws {
        SuggestionAvailability.override = .available
        isolateState(services: "")
        let counter = CallCounter()
        // Nothing is on the watchlist and nothing is rated.
        SuggestionGenerator.responder = {
            StubSession(answers: [.success(RawPick(pick: 1, vibe: "It's on your watchlist and you gave it 4 stars."))], counter: counter)
        }
        let outcome = await SuggestionGenerator.generate()
        guard case .suggestion(let accepted) = outcome else { return XCTFail("\(outcome)") }
        let shown = ([accepted.lead ?? ""] + accepted.facts.map(\.text) + [accepted.spoken]).joined(separator: " ").lowercased()
        XCTAssertFalse(shown.contains("watchlist"), shown)
        XCTAssertFalse(shown.contains("rated"), shown)
        XCTAssertFalse(shown.contains("4 stars"), shown)
        XCTAssertTrue(accepted.facts.contains(.notWatchedYet))
        // Free text where a vibe belongs fails the strict parse: the app's own pick.
        XCTAssertTrue(accepted.isFallback)
        XCTAssertEqual(counter.picks, 1)
    }

    func testGeneratorUsesTheModelsPickWithAppFacts() async throws {
        SuggestionAvailability.override = .available
        let store = isolateState(services: "99")
        store.setStatus(.wantToWatch, for: devil.id)
        let counter = CallCounter()
        SuggestionGenerator.responder = { StubSession(answers: [.success(RawPick(pick: 1, vibe: "scares"))], counter: counter) }
        let outcome = await SuggestionGenerator.generate()
        XCTAssertEqual(outcome, .suggestion(AcceptedSuggestion(
            movieId: devil.id, title: "The Devil's Rain", year: 1975, lead: "Good for a scare.",
            facts: [.onWatchlist, .notWatchedYet, .streaming("Shudder"), .category("Horror")], isFallback: false
        )))
        XCTAssertEqual(counter.picks, 1)
        XCTAssertEqual(counter.prompts.first?.contains("1. The Devil's Rain (1975)"), true)
    }

    func testInvalidPickThrownErrorAndTimeoutShowTheTopCandidateOnce() async throws {
        SuggestionAvailability.override = .available
        let store = isolateState(services: "")
        store.setStatus(.wantToWatch, for: devil.id)
        let expected = AcceptedSuggestion(
            movieId: devil.id, title: "The Devil's Rain", year: 1975, lead: "Picked from your watchlist and services.",
            facts: [.onWatchlist, .notWatchedYet, .category("Horror")], isFallback: true
        )

        let invalid = CallCounter()
        SuggestionGenerator.responder = { StubSession(answers: [.success(RawPick(pick: 13, vibe: "laughs"))], counter: invalid) }
        let a = await SuggestionGenerator.generate()
        XCTAssertEqual(a, .suggestion(expected))
        XCTAssertEqual(invalid.picks, 1, "one attempt only")

        let thrown = CallCounter()
        SuggestionGenerator.responder = { StubSession(answers: [.failure(IntentError.catalogUnavailable)], counter: thrown) }
        let b = await SuggestionGenerator.generate()
        XCTAssertEqual(b, .suggestion(expected))
        XCTAssertEqual(thrown.picks, 1)

        let slow = CallCounter()
        SuggestionGenerator.timeout = .milliseconds(100)
        SuggestionGenerator.responder = { StubSession(answers: [.success(RawPick(pick: 2, vibe: "scares"))], counter: slow, delay: .seconds(5)) }
        let start = Date()
        let c = await SuggestionGenerator.generate()
        XCTAssertLessThan(Date().timeIntervalSince(start), 2.0, "returns at the timeout, not when the model finishes")
        XCTAssertEqual(c, .suggestion(expected))
        XCTAssertEqual(SuggestionGenerator.lastTiming?.timedOut, true)
        XCTAssertEqual(slow.picks, 1)
    }

    func testDefaultBudgetIsOneAttemptInTwoAndAHalfSeconds() {
        SuggestionGenerator.reset()
        XCTAssertEqual(SuggestionGenerator.timeout, .milliseconds(2500))
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            XCTAssertEqual(OnDeviceSuggestionSession.maximumResponseTokens, 24)
        }
        #endif
    }

    func testNothingToPickOffersSpin() async {
        SuggestionAvailability.override = .available
        let store = isolateState(services: "")
        for movie in catalog.movies { store.setStatus(.watched, for: movie.id) }
        let counter = CallCounter()
        SuggestionGenerator.responder = { StubSession(answers: [], counter: counter) }
        let outcome = await SuggestionGenerator.generate()
        XCTAssertEqual(outcome, .offerSpin(.failed))
        XCTAssertEqual(counter.picks, 0)
    }

    func testPrewarmRunsOnlyWhenTheGateIsReady() {
        let counter = CallCounter()
        SuggestionGenerator.responder = { StubSession(answers: [], counter: counter) }
        let controller = SuggestionController()
        SuggestionAvailability.override = .unavailable
        controller.prewarm()
        XCTAssertEqual(counter.prewarms, 0)
        SuggestionAvailability.override = .temporarilyUnavailable
        controller.prewarm()
        XCTAssertEqual(counter.prewarms, 0)
        SuggestionAvailability.override = .available
        controller.prewarm()
        XCTAssertEqual(counter.prewarms, 1)
    }

    func testIntentSpeaksAppFactsAndDoesNotSpinWhenTheModelFails() async {
        SuggestionAvailability.override = .available
        isolateState(services: "")
        let counter = CallCounter()
        SuggestionGenerator.responder = { StubSession(answers: [.failure(IntentError.catalogUnavailable)], counter: counter) }
        let history = SpinHistoryStore(fileStore: nil)
        IntentRuntime.history = { history }
        _ = try? await WhatShouldIWatchIntent().perform()
        XCTAssertTrue(history.results.isEmpty)
        XCTAssertNil(AppRouter.shared.pendingSpin)
    }

    /// Opt-in device/simulator measurement of the real on-device model.
    /// Skips (with the reason) when Foundation Models can't run here.
    func testLiveModelLatencyWhenAvailable() async throws {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { throw XCTSkip("iOS 26+ only") }
        SuggestionAvailability.reset()
        let status = SuggestionAvailability.mapSystemAvailability()
        guard status == .available else { throw XCTSkip("Foundation Models unavailable here: \(status)") }
        let real = try Self.bundledCatalog()
        let rows = PickMovie.rows(catalog: real, ratings: PersonalRatings(), recentIDs: [], services: MyServices())
        var rng = SeededGenerator(seed: 1)
        let prompt = PickPrompt.prompt(for: PickCandidates.select(rows, using: &rng))
        let clock = ContinuousClock()

        let cold = OnDeviceSuggestionSession()
        let coldStart = clock.now
        let coldAnswer = try await cold.pick(prompt: prompt)
        let coldTime = coldStart.duration(to: clock.now)

        let warm = OnDeviceSuggestionSession()
        let prewarmStart = clock.now
        warm.prewarm()
        let prewarmCall = prewarmStart.duration(to: clock.now)
        try await Task.sleep(for: .seconds(2))
        let warmStart = clock.now
        let warmAnswer = try await warm.pick(prompt: prompt)
        let warmTime = warmStart.duration(to: clock.now)
        print("MRT-LATENCY cold=\(coldTime) prewarmCall=\(prewarmCall) warm=\(warmTime) chars=\(prompt.count) answers=\(coldAnswer) \(warmAnswer)")
        XCTAssertTrue((1...12).contains(warmAnswer.pick))
        #else
        throw XCTSkip("FoundationModels not in this SDK")
        #endif
    }

    // MARK: Fixtures

    static func bundledCatalog() throws -> MovieCatalog {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "movies", withExtension: "json"), "the app's bundled movies.json")
        return try MovieCatalog.decode(from: Data(contentsOf: url))
    }

    @discardableResult
    private func isolateState(services: String) -> PersonalRatingsStore {
        let store = PersonalRatingsStore(fileStore: nil)
        IntentRuntime.ratings = { store }
        let defaults = UserDefaults(suiteName: "mrt.pick.tests.\(UUID().uuidString)")!
        defaults.set(services, forKey: MyServices.storageKey)
        IntentRuntime.defaults = { defaults }
        let history = SpinHistoryStore(fileStore: nil)
        IntentRuntime.history = { history }
        SuggestionGenerator.seed = SuggestionGenerator.seed ?? 1
        return store
    }

    private static func movie(_ id: String, status: WatchStatus? = nil, halfStars: Int? = nil,
                              recent: Bool = false, onService: Bool = false, free: Bool = false) -> PickMovie {
        PickMovie(id: id, title: id, year: 2000, genre: "Drama", categories: [], status: status, halfStars: halfStars,
                  recent: recent, serviceProvider: onService ? "Service" : nil, freeProvider: free ? "Free" : nil)
    }

    private static func candidateMovie(_ m: [String: Any]) -> PickMovie {
        movie(m["id"] as? String ?? "?",
              status: (m["status"] as? String).flatMap(WatchStatus.init(rawValue:)),
              halfStars: m["halfStars"] as? Int,
              recent: m["recent"] as? Bool ?? false,
              onService: m["onService"] as? Bool ?? false,
              free: m["free"] as? Bool ?? false)
    }

    /// Builds the row through the same provider matching the app uses.
    private static func composerMovie(_ c: [String: Any]) -> PickMovie {
        let names = (c["stream"] as? [String] ?? []) + (c["free"] as? [String] ?? []) + (c["myServices"] as? [String] ?? [])
        var ids: [String: Int] = [:]
        for name in names where ids[name] == nil { ids[name] = ids.count + 1 }
        let stream = (c["stream"] as? [String] ?? []).map { StreamingInfo.Provider(id: ids[$0]!, name: $0) }
        let mine = MyServices(ids: Set((c["myServices"] as? [String] ?? []).compactMap { ids[$0] }))
        return PickMovie(
            id: "case", title: "Case", year: 2000, genre: "Horror",
            categories: (c["category"] as? String).map { [$0] } ?? [],
            status: (c["status"] as? String).flatMap(WatchStatus.init(rawValue:)),
            halfStars: c["halfStars"] as? Int,
            recent: false,
            serviceProvider: PickMovie.firstService(stream: stream, services: mine),
            freeProvider: (c["free"] as? [String])?.first
        )
    }

    private final class CallCounter: @unchecked Sendable {
        var picks = 0
        var prewarms = 0
        var prompts: [String] = []
    }

    private struct StubSession: SuggestionResponding {
        var answers: [Result<RawPick, Error>]
        var counter: CallCounter
        var delay: Duration?

        func prewarm() { counter.prewarms += 1 }

        func pick(prompt: String) async throws -> RawPick {
            let i = counter.picks
            counter.picks += 1
            counter.prompts.append(prompt)
            if let delay { try? await Task.sleep(for: delay) }
            guard i < answers.count else { throw IntentError.catalogUnavailable }
            return try answers[i].get()
        }
    }

    private static func makeCatalog() -> MovieCatalog {
        let horror = RouletteCategory(
            id: "cat-horror", name: "Horror", colorHex: "#C25B5E",
            movieIds: ["the-devils-rain-1975", "the-thing-1982", "the-thing-2011"]
        )
        let cult = RouletteCategory(
            id: "cat-cult", name: "Cult", colorHex: "#8670AE",
            movieIds: ["the-devils-rain-1975", "no-stream"]
        )
        let shudder = StreamingInfo.Provider(id: 99, name: "Shudder")
        let netflix = StreamingInfo.Provider(id: 8, name: "Netflix")
        let devil = Movie(
            id: "the-devils-rain-1975", title: "The Devil's Rain", year: 1975, genre: "Horror",
            categories: ["cat-horror", "cat-cult"], episodeIds: ["Buzzsprout-20099500"],
            episodeTitle: "The Devil's Rain",
            streaming: StreamingInfo(stream: [shudder, netflix])
        )
        let thing82 = Movie(id: "the-thing-1982", title: "The Thing", year: 1982, genre: "Horror", categories: ["cat-horror"])
        let thing11 = Movie(id: "the-thing-2011", title: "The Thing", year: 2011, genre: "Horror", categories: ["cat-horror"])
        let plain = Movie(id: "no-stream", title: "Quiet Title", year: 1999, genre: "Drama", categories: ["cat-cult"])
        return MovieCatalog(categories: [horror, cult], movies: [devil, thing82, thing11, plain])
    }
}

/// House Rules can't drift from what the app ships: the Siri and Shortcuts
/// lists are compared with the compiled App Intents metadata in the app bundle.
@MainActor
final class HouseRulesTests: XCTestCase {
    private func metadata() throws -> [String: Any] {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "extract", withExtension: "actionsdata", subdirectory: "Metadata.appintents"),
            "the app's compiled App Intents metadata"
        )
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    func testSiriSectionListsEveryAppShortcutPhraseExactly() throws {
        let shortcuts = try XCTUnwrap(try metadata()["autoShortcuts"] as? [[String: Any]])
        XCTAssertLessThanOrEqual(shortcuts.count, 10, "the system allows 10 App Shortcuts")
        var compiled: [String: [String]] = [:]
        for s in shortcuts {
            let id = try XCTUnwrap(s["actionIdentifier"] as? String)
            let templates = try XCTUnwrap(s["phraseTemplates"] as? [[String: Any]])
            compiled[id] = templates.compactMap { $0["key"] as? String }
        }
        let listed = Dictionary(uniqueKeysWithValues: HouseRules.siriShortcuts.map { ($0.intent, $0.phrases) })
        XCTAssertEqual(Set(listed.keys), Set(compiled.keys))
        for (id, phrases) in compiled {
            XCTAssertEqual(listed[id].map(Set.init), Set(phrases), id)
        }

        let text = HouseRules.sections.flatMap(\.rows).map(\.text).joined(separator: "\n")
        for phrases in compiled.values {
            for phrase in phrases {
                XCTAssertTrue(text.contains("“\(HouseRules.spoken(phrase))”"), phrase)
            }
        }
        XCTAssertTrue(text.contains("“Pick a movie for me in Movie Roulette”"))
        XCTAssertTrue(text.contains("“What should I watch in Movie Roulette”"))
        XCTAssertFalse(text.contains("What should we watch"))
    }

    func testShortcutsAppSectionListsEveryDiscoverableAction() throws {
        let actions = try XCTUnwrap(try metadata()["actions"] as? [String: [String: Any]])
        let discoverable = actions.values
            .filter { $0["isDiscoverable"] as? Bool == true }
            .compactMap { ($0["title"] as? [String: Any])?["key"] as? String }
        XCTAssertEqual(Set(discoverable), Set(HouseRules.shortcutsActions))
        XCTAssertEqual(HouseRules.shortcutsActions.count, Set(HouseRules.shortcutsActions).count)
        XCTAssertTrue(discoverable.contains("Pick for Me"))
        XCTAssertFalse(discoverable.contains("What Should I Watch"))
    }

    /// ASC 90626: App Intents metadata can't contain "apple".
    func testNoAppleInAnyUserVisibleIntentString() throws {
        var hits: [String] = []
        func scan(_ value: Any) {
            if let dict = value as? [String: Any] {
                if dict["alternatives"] != nil, let key = dict["key"] as? String, key.lowercased().contains("apple") {
                    hits.append(key)
                }
                if let format = dict["formatString"] as? String, format.lowercased().contains("apple") {
                    hits.append(format)
                }
                dict.values.forEach(scan)
            } else if let array = value as? [Any] {
                array.forEach(scan)
            }
        }
        scan(try metadata())
        XCTAssertEqual(hits, [])
    }

    func testPickForMeCopyAndSections() {
        XCTAssertEqual(PickForMeCopy.buttonTitle, "Pick for Me")
        XCTAssertEqual(PickForMeCopy.buttonSubtitle, "Not random: one movie chosen for you, and why it fits.")
        XCTAssertEqual(PickForMeCopy.sheetTitle, "Picked for You")
        XCTAssertEqual(
            HouseRules.sections.compactMap(\.title),
            // Same order and names as Android PR #13 where they apply.
            ["The Wheel", "Spin or Pick for Me", "Search", "Your Lists", "Siri and Shortcuts", "Home Screen Widget", "Good to Know"]
        )
        let ids = HouseRules.sections.flatMap(\.rows).map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "row ids are unique")
        // The email feature keeps its own name; Pick for Me never uses it.
        let text = HouseRules.sections.flatMap(\.rows).map(\.text).joined(separator: " ")
        XCTAssertFalse(text.contains("Suggest a Movie"))
    }
}
