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

    // MARK: Prompt

    func testPromptIsOnDeviceOnlyAndIncludesWatchlistRatingHistoryAndServices() {
        var ratings = PersonalRatings()
        ratings.setStatus(.wantToWatch, for: devil.id)
        ratings.setHalfStars(9, for: devil.id)
        // Rating a want-to-watch title marks it watched; put it back on the list
        // after the rating so the prompt still carries both facts.
        ratings.setStatus(.wantToWatch, for: devil.id)
        XCTAssertEqual(ratings.status(for: devil.id), .wantToWatch)
        XCTAssertEqual(ratings.halfStars(for: devil.id), 9)

        let older = SpinResult(movieId: thing82.id, categoryId: "cat-horror", timestamp: Date(timeIntervalSince1970: 1))
        let newer = SpinResult(movieId: devil.id, categoryId: "cat-horror", timestamp: Date(timeIntervalSince1970: 100))
        let recent = SuggestionPrompt.recentIDs(from: [older, newer], limit: 10)
        XCTAssertEqual(recent, [devil.id, thing82.id])

        let services = MyServices(ids: [99])
        let context = SuggestionPrompt.context(
            catalog: catalog, ratings: ratings, recentIDs: recent, services: services
        )
        XCTAssertEqual(context.serviceNames, ["Shudder"])
        let prompt = SuggestionPrompt.prompt(from: context)
        let devilLine = context.movies.first { $0.id == devil.id }.map { SuggestionPrompt.line(for: $0) } ?? ""

        XCTAssertTrue(devilLine.contains("id=the-devils-rain-1975"))
        XCTAssertTrue(devilLine.contains("title=The Devil's Rain"))
        XCTAssertTrue(devilLine.contains("year=1975"))
        XCTAssertTrue(devilLine.contains("genre=Horror"))
        XCTAssertTrue(devilLine.contains("watchlist"))
        XCTAssertTrue(devilLine.contains("rated=\(HalfStars.label(9))"))
        XCTAssertTrue(devilLine.contains("recent"))
        XCTAssertTrue(devilLine.contains("on=Shudder"))
        XCTAssertTrue(prompt.contains("Listener’s services: Shudder"))
        XCTAssertTrue(prompt.contains(devilLine))
        XCTAssertTrue(SuggestionPrompt.instructions.contains("Do not invent a movie"))
        XCTAssertTrue(SuggestionPrompt.instructions.contains("Prefer watchlist"))

        // Privacy: the prompt is assembled from local facts only — no URLs, no plots.
        XCTAssertFalse(prompt.lowercased().contains("http"))
        XCTAssertFalse(prompt.lowercased().contains("tmdb"))
        XCTAssertFalse(prompt.lowercased().contains("plot"))
        XCTAssertFalse(prompt.lowercased().contains("synopsis"))
        XCTAssertFalse(prompt.contains("{"))
    }

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

    // MARK: Parsing and retry

    func testValidSuggestionIsAcceptedAndUnknownOrEmptyWhyIsRejected() {
        let ids: Set<String> = [devil.id, thing82.id]
        let ok = SuggestionValidation.accept(
            WatchSuggestionDraft(movieId: "  the-devils-rain-1975  ", why: "  It’s on your watchlist.  "),
            catalogIDs: ids
        )
        XCTAssertEqual(ok?.movieId, devil.id)
        XCTAssertEqual(ok?.why, "It’s on your watchlist.")

        XCTAssertNil(SuggestionValidation.accept(
            WatchSuggestionDraft(movieId: "invented-movie", why: "Because I said so."),
            catalogIDs: ids
        ))
        XCTAssertNil(SuggestionValidation.accept(
            WatchSuggestionDraft(movieId: devil.id, why: "   "),
            catalogIDs: ids
        ))
        XCTAssertNil(SuggestionValidation.accept(
            WatchSuggestionDraft(movieId: "The Devil's Rain", why: "A made-up title, not an id."),
            catalogIDs: ids
        ))
    }

    func testResolverRetriesOnceThenFallsBackToOfferingSpin() {
        let ids: Set<String> = [devil.id]
        let valid = WatchSuggestionDraft(movieId: devil.id, why: "It’s Horror, and it’s on Shudder.")
        let invalid = WatchSuggestionDraft(movieId: "nope", why: "Hallucinated.")
        let empty = WatchSuggestionDraft(movieId: devil.id, why: "")

        let firstGood = SuggestionResolver.resolve(attempts: [.success(valid)], catalogIDs: ids)
        XCTAssertEqual(firstGood, .suggestion(AcceptedSuggestion(movieId: devil.id, why: valid.why)))

        let retryWorks = SuggestionResolver.resolve(
            attempts: [.success(invalid), .success(valid)],
            catalogIDs: ids
        )
        XCTAssertEqual(retryWorks, .suggestion(AcceptedSuggestion(movieId: devil.id, why: valid.why)))

        let errorThenValid = SuggestionResolver.resolve(
            attempts: [.failure(IntentError.catalogUnavailable), .success(valid)],
            catalogIDs: ids
        )
        XCTAssertEqual(errorThenValid, .suggestion(AcceptedSuggestion(movieId: devil.id, why: valid.why)))

        let bothBad = SuggestionResolver.resolve(
            attempts: [.success(invalid), .success(empty)],
            catalogIDs: ids
        )
        XCTAssertEqual(bothBad, .offerSpin(.failed))

        let bothThrow = SuggestionResolver.resolve(
            attempts: [.failure(IntentError.catalogUnavailable), .failure(IntentError.unknownMovie)],
            catalogIDs: ids
        )
        XCTAssertEqual(bothThrow, .offerSpin(.failed))

        // A third attempt is ignored; two failures already settle on the fallback.
        let ignoresThird = SuggestionResolver.resolve(
            attempts: [.success(invalid), .success(empty), .success(valid)],
            catalogIDs: ids
        )
        XCTAssertEqual(ignoresThird, .offerSpin(.failed))
    }

    // MARK: Generator fallback — no automatic spin

    func testGeneratorOffersSpinWhenUnavailableAndDoesNotCallTheSessionOrSpin() async {
        SuggestionAvailability.override = .unavailable
        var called = false
        SuggestionGenerator.responder = {
            called = true
            return StubSession(drafts: [])
        }
        let history = SpinHistoryStore(fileStore: nil)
        IntentRuntime.history = { history }

        let outcome = await SuggestionGenerator.generate()
        XCTAssertEqual(outcome, .offerSpin(.unavailable))
        XCTAssertFalse(called, "the model must not be asked when the gate is closed")
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
        var called = false
        SuggestionGenerator.responder = {
            called = true
            return StubSession(drafts: [])
        }
        let notReady = await SuggestionGenerator.generate()
        XCTAssertEqual(notReady, .notReady)
        XCTAssertFalse(called)
    }

    func testGeneratorAcceptsAValidStubAndRetriesAnInvalidId() async {
        SuggestionAvailability.override = .available
        let valid = WatchSuggestionDraft(movieId: devil.id, why: "It’s on your watchlist, and it’s on Shudder.")
        SuggestionGenerator.responder = {
            StubSession(drafts: [
                WatchSuggestionDraft(movieId: "hallucinated", why: "No."),
                valid,
            ])
        }
        let accepted = await SuggestionGenerator.generate()
        XCTAssertEqual(accepted, .suggestion(AcceptedSuggestion(movieId: devil.id, why: valid.why)))

        SuggestionGenerator.responder = {
            StubSession(drafts: [
                WatchSuggestionDraft(movieId: "hallucinated", why: "No."),
                WatchSuggestionDraft(movieId: "still-wrong", why: "No again."),
            ])
        }
        let failed = await SuggestionGenerator.generate()
        XCTAssertEqual(failed, .offerSpin(.failed))
    }

    func testIntentDoesNotSpinWhenTheModelFails() async {
        SuggestionAvailability.override = .available
        SuggestionGenerator.responder = { StubSession(drafts: [], error: IntentError.catalogUnavailable) }
        let history = SpinHistoryStore(fileStore: nil)
        IntentRuntime.history = { history }
        _ = try? await WhatShouldIWatchIntent().perform()
        XCTAssertTrue(history.results.isEmpty)
        XCTAssertNil(AppRouter.shared.pendingSpin)
    }

    // MARK: Fixtures

    private struct StubSession: SuggestionResponding {
        var drafts: [WatchSuggestionDraft]
        var error: Error?
        private final class Cursor: @unchecked Sendable { var index = 0 }
        private let cursor = Cursor()

        func suggest(prompt: String) async throws -> WatchSuggestionDraft {
            if let error { throw error }
            // The prompt is local-only; a stub still sees it so tests can
            // assert generate() built one, but we don't inspect it here.
            _ = prompt
            let i = cursor.index
            cursor.index += 1
            guard i < drafts.count else { throw IntentError.catalogUnavailable }
            return drafts[i]
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
