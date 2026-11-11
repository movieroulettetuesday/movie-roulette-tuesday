import XCTest
import MRTCore
import MRTShared
@testable import MovieRouletteTuesdayTV

/// App Intent decisions on tvOS. No Siri session, no Foundation Models,
/// and no network: stores are in memory or a temp file.
@MainActor
final class TVIntentsTests: XCTestCase {
    private var catalog: MovieCatalog!
    private var devil: Movie!
    private var plain: Movie!

    override func setUp() {
        super.setUp()
        let loaded = Self.makeCatalog()
        catalog = loaded
        devil = loaded.movie(withId: "the-devils-rain-1975")
        plain = loaded.movie(withId: "no-stream")
        IntentRuntime.reset()
        IntentRuntime.opensApp = false
        IntentRuntime.catalog = { loaded }
        AppRouter.shared.pendingURL = nil
        AppRouter.shared.pendingSpin = nil
    }

    override func tearDown() {
        IntentRuntime.reset()
        AppRouter.shared.pendingURL = nil
        AppRouter.shared.pendingSpin = nil
        super.tearDown()
    }

    // MARK: What should I watch (always offers Spin, never auto-spins)

    func testWhatShouldIWatchOffersSpinAndDoesNotSpin() async throws {
        let history = SpinHistoryStore(fileStore: nil)
        IntentRuntime.history = { history }
        _ = try await WhatShouldIWatchIntent().perform()
        XCTAssertTrue(history.results.isEmpty)
        XCTAssertNil(AppRouter.shared.pendingSpin)
        XCTAssertNil(AppRouter.shared.pendingURL)
        XCTAssertFalse(WhatShouldIWatchIntent.openAppWhenRun)
        XCTAssertEqual(SuggestionSpeech.unavailable, "Suggestions aren’t available on this device. I can spin the wheel instead.")
    }

    // MARK: Entities and queries

    func testQueryResolvesByTitleYearAndGenreAndFailsCleanly() async throws {
        IntentRuntime.episodes = { [] }
        let query = MovieEntityQuery()
        let rain = try await query.entities(matching: "devils rain")
        XCTAssertEqual(rain.map(\.id), ["the-devils-rain-1975"])
        XCTAssertEqual(rain.first?.subtitle, "1975 · Horror")

        let both = try await query.entities(matching: "The Thing")
        XCTAssertEqual(Set(both.map(\.id)), ["the-thing-1982", "the-thing-2011"])
        let one = try await query.entities(matching: "The Thing 1982")
        XCTAssertEqual(one.map(\.id), ["the-thing-1982"])

        let drama = try await query.entities(matching: "Drama")
        XCTAssertEqual(drama.map(\.id), ["no-stream"])
        let cult = try await query.entities(matching: "Cult")
        XCTAssertTrue(cult.map(\.id).contains("the-devils-rain-1975"))

        let missing = try await query.entities(for: ["no-such-movie", "the-thing-1982"])
        XCTAssertEqual(missing.map(\.id), ["the-thing-1982"])
        let none = try await query.entities(matching: "zzzz-not-a-movie")
        XCTAssertTrue(none.isEmpty)

        let episodes = [
            PodcastEpisode(guid: "Buzzsprout-1", title: "The Devil's Rain", pubDate: Date(timeIntervalSince1970: 10), season: 4, episode: 39),
            PodcastEpisode(guid: "other", title: "Something Else"),
        ]
        IntentRuntime.episodes = { episodes }
        let episodeQuery = EpisodeEntityQuery()
        let found = try await episodeQuery.entities(matching: "devil")
        XCTAssertEqual(found.map(\.id), ["Buzzsprout-1"])
        let missingEpisodes = try await episodeQuery.entities(for: ["missing-guid"])
        XCTAssertTrue(missingEpisodes.isEmpty)
        let withLabel = MovieEntity(movie: devil, catalog: catalog, episodesByGUID: ["Buzzsprout-20099500": episodes[0]])
        XCTAssertEqual(withLabel.subtitle, "1975 · Horror · S4E39")
    }

    // MARK: Watchlist

    func testWatchlistAddAndMarkWatchedDoNotInventARating() {
        var ratings = PersonalRatings()
        ratings.setStatus(.wantToWatch, for: devil.id)
        ratings.setStatus(.watched, for: "the-thing-1982")
        ratings.setHalfStars(8, for: "the-thing-2011")
        let listed = WatchlistReading.wantToWatch(in: ratings, catalog: catalog)
        XCTAssertEqual(listed.map(\.id), [devil.id])
        XCTAssertTrue(WatchlistReading.speech(for: listed).contains(devil.title))
        XCTAssertEqual(WatchlistReading.speech(for: []), "Your watchlist is empty.")

        let stars = ratings.halfStars(for: "the-thing-2011")
        WatchlistEditing.add(movieID: "the-thing-2011", ratings: &ratings)
        XCTAssertEqual(ratings.status(for: "the-thing-2011"), .wantToWatch)
        XCTAssertEqual(ratings.halfStars(for: "the-thing-2011"), stars)

        WatchlistEditing.markWatched(movieID: devil.id, ratings: &ratings)
        XCTAssertEqual(ratings.status(for: devil.id), .watched)
        XCTAssertNil(ratings.halfStars(for: devil.id))
        XCTAssertNil(ratings.rating(for: devil.id))
        XCTAssertEqual(WatchlistReading.wantToWatch(in: ratings, catalog: catalog).map(\.id), ["the-thing-2011"])
    }

    func testAddAndMarkWatchedPerformWriteTheStore() async throws {
        let store = makeRatingsStore()
        IntentRuntime.ratings = { store }
        store.setHalfStars(7, for: devil.id)
        let add = AddToWatchlistIntent()
        add.movie = MovieEntity(movie: devil, catalog: catalog)
        _ = try await add.perform()
        XCTAssertEqual(store.status(for: devil.id), .wantToWatch)
        XCTAssertEqual(store.halfStars(for: devil.id), 7)

        let mark = MarkWatchedIntent()
        mark.movie = MovieEntity(movie: plain, catalog: catalog)
        _ = try await mark.perform()
        XCTAssertEqual(store.status(for: plain.id), .watched)
        XCTAssertNil(store.halfStars(for: plain.id))

        store.setStatus(.watched, for: "the-thing-1982")
        let shown = ShowWatchlistIntent()
        _ = try await shown.perform()
        XCTAssertEqual(store.status(for: devil.id), .wantToWatch)
        XCTAssertEqual(store.status(for: "the-thing-1982"), .watched)
    }

    // MARK: Where to watch and providers

    func testWhereToWatchMatchesDisplayAndFavorsMyServices() {
        let empty = WhereToWatchSpeech.line(for: plain, services: MyServices())
        XCTAssertTrue(empty.spoken.contains(WhereToWatchDisplay.emptyMessage))
        XCTAssertTrue(empty.providerNames.isEmpty)
        XCTAssertTrue(WhereToWatchDisplay(movie: plain).showsEmptyMessage)

        let all = WhereToWatchSpeech.line(for: devil, services: MyServices())
        XCTAssertEqual(all.providerNames, ["Shudder", "Netflix"])
        XCTAssertTrue(all.spoken.contains("Shudder"))

        let mine = WhereToWatchSpeech.line(for: devil, services: MyServices(ids: [99]))
        XCTAssertEqual(mine.providerNames.first, "Shudder")
        XCTAssertTrue(mine.providerNames.contains("Netflix"))
        XCTAssertTrue(mine.spoken.contains("your service"))
    }

    func testWhereToWatchPerformDoesNotNavigate() async throws {
        let defaults = UserDefaults(suiteName: "mrt.tv.intent.tests.\(UUID().uuidString)")!
        defaults.set("99", forKey: MyServices.storageKey)
        IntentRuntime.defaults = { defaults }
        let intent = WhereToWatchIntent()
        intent.movie = MovieEntity(movie: devil, catalog: catalog)
        _ = try await intent.perform()
        XCTAssertNil(AppRouter.shared.pendingURL)
    }

    func testOpenOnProviderUsesProviderLaunchingURLs() async throws {
        var opened: [URL] = []
        IntentRuntime.canOpenURL = { _ in false }
        IntentRuntime.openURL = { url in
            opened.append(url)
            return true
        }
        let intent = OpenOnProviderIntent()
        intent.movie = MovieEntity(movie: devil, catalog: catalog)
        intent.provider = .netflix
        _ = try await intent.perform()

        let expected = ProviderLaunching.destination(
            for: StreamingInfo.Provider(id: 8, name: "Netflix"), movie: devil
        ).attempts { _ in false }
        XCTAssertEqual(opened, [try XCTUnwrap(expected.first)])
        XCTAssertEqual(opened.first?.scheme, "https")

        opened.removeAll()
        IntentRuntime.canOpenURL = { $0.scheme == "nflx" }
        intent.movie = MovieEntity(movie: plain, catalog: catalog)
        _ = try await intent.perform()
        let emptyProviders = ProviderOpenPlan.choice(for: .netflix, movie: plain, canOpen: { $0.scheme == "nflx" })
        XCTAssertEqual(opened.first, emptyProviders.urls.first)
        XCTAssertEqual(opened.first?.scheme, "nflx")
        XCTAssertFalse(emptyProviders.urls.isEmpty, "a mapped provider still has a URL when the movie lists none")
    }

    func testOpenMovieRoutesAndRejectsAnUnknownId() async throws {
        let intent = OpenMovieIntent()
        intent.movie = MovieEntity(movie: devil, catalog: catalog)
        _ = try await intent.perform()
        XCTAssertEqual(AppRouter.shared.pendingURL, DeepLink.movie(id: devil.id).url)

        let missing = OpenMovieIntent()
        missing.movie = MovieEntity(id: "nope", title: "Nope", year: 1999, genre: "G", categoryNames: [], episodeLabel: nil)
        do {
            _ = try await missing.perform()
            XCTFail("unknown id should fail")
        } catch let error as IntentError {
            XCTAssertEqual(error, .unknownMovie)
        }
    }

    // MARK: Latest episode

    func testLatestEpisodeEmptyCacheIsATypedErrorAndOffersToOpen() async throws {
        IntentRuntime.episodes = { [] }
        do {
            _ = try LatestEpisodeLogic.pick(episodes: [], trackIDs: [:])
            XCTFail("empty cache")
        } catch let error as LatestEpisodeFailure {
            XCTAssertEqual(error, .emptyCache)
        }
        _ = try await LatestEpisodeIntent().perform()
        XCTAssertNil(AppRouter.shared.pendingURL, "empty cache does not navigate; the snippet offers to open")
    }

    func testLatestEpisodeOpensThePageAndListenUsesAppleLinks() async throws {
        let episode = PodcastEpisode(
            guid: "Buzzsprout-20099500", title: "The Devil's Rain",
            pubDate: Date(timeIntervalSince1970: 1_700_000_000), season: 4, episode: 39
        )
        IntentRuntime.episodes = { [episode] }
        IntentRuntime.appleTrackIDs = { ["Buzzsprout-20099500": 55] }
        _ = try await LatestEpisodeIntent().perform()
        XCTAssertEqual(AppRouter.shared.pendingURL, DeepLink.episode(guid: episode.guid).url)

        let exact = try LatestEpisodeLogic.pick(episodes: [episode], trackIDs: ["Buzzsprout-20099500": 55])
        XCTAssertTrue(exact.isExactEpisode)
        XCTAssertEqual(exact.listenURL?.absoluteString, "https://podcasts.apple.com/us/podcast/id1666123849?i=55")
        XCTAssertTrue(exact.speech.contains("The Devil's Rain"))
        XCTAssertTrue(exact.speech.contains("S4E39"))
        let show = try LatestEpisodeLogic.pick(episodes: [episode], trackIDs: [:])
        XCTAssertFalse(show.isExactEpisode)
        XCTAssertEqual(show.listenURL, ShowInfo.mrt.applePodcastsURL)

        var opened: [URL] = []
        IntentRuntime.openURL = { url in
            opened.append(url)
            return true
        }
        _ = try await ListenInApplePodcastsIntent(episodeGUID: episode.guid).perform()
        XCTAssertEqual(opened, [try XCTUnwrap(exact.listenURL)])
    }

    // MARK: Spin handoff

    func testSpinRecordsHistoryOnceAndHandsOffTheSameResult() async throws {
        let history = SpinHistoryStore(fileStore: nil)
        IntentRuntime.history = { history }
        let router = AppRouter.shared
        IntentRuntime.router = { router }
        _ = try await SpinMovieRouletteIntent().perform()
        XCTAssertEqual(history.results.count, 1)
        let saved = try XCTUnwrap(history.results.first)
        let pending = try XCTUnwrap(router.pendingSpin)
        XCTAssertEqual(pending.movieID, saved.movieId)
        XCTAssertEqual(pending.creditedCategoryID, saved.categoryId)
        XCTAssertEqual(pending.resultID, saved.id)
        XCTAssertEqual(router.pendingURL, DeepLink.spin.url)

        let data = try JSONEncoder().encode(catalog)
        let model = RouletteViewModel(catalogSource: DataCatalogSource(data: data), history: history)
        await model.load()
        XCTAssertTrue(model.installHandedOffReveal(pending))
        XCTAssertEqual(history.results.count, 1, "the wheel must not record the Siri spin again")
        XCTAssertEqual(model.reveal?.movie.id, pending.movieID)
        XCTAssertEqual(model.reveal?.id, pending.resultID)
        XCTAssertEqual(model.reveal?.isJackpot, pending.isJackpot)
    }

    func testHandedOffWheelLandsOnTheRequestedSegment() throws {
        let even = WheelGeometry(segmentCount: 4)
        for index in 0..<4 {
            let target = try XCTUnwrap(even.targetRotation(landingOn: index, from: 20, fullTurns: 5))
            XCTAssertEqual(even.segmentIndex(forRotation: target), index)
            XCTAssertGreaterThan(target, 20)
        }
        let weighted = WheelGeometry(weights: [1, 3])
        for index in 0..<2 {
            let target = try XCTUnwrap(weighted.targetRotation(landingOn: index, from: -15, fullTurns: 3))
            XCTAssertEqual(weighted.segmentIndex(forRotation: target), index)
        }
        XCTAssertNil(even.targetRotation(landingOn: 9, from: 0, fullTurns: 2))
        XCTAssertNil(even.targetRotation(landingOn: 0, from: .nan, fullTurns: 2))
    }

    func testSpinAndEpisodeRoutes() throws {
        XCTAssertEqual(DeepLink(url: try XCTUnwrap(URL(string: "mrt://spin"))), .spin)
        XCTAssertEqual(DeepLink(url: DeepLink.episodes.url), .episodes)
        XCTAssertNil(DeepLink(url: try XCTUnwrap(URL(string: "mrt://nope"))))
    }

    // MARK: Fixtures

    private func makeRatingsStore() -> PersonalRatingsStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mrt-tv-intent-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("personal-ratings.json")
        return PersonalRatingsStore(fileStore: PersonalRatingsFileStore(fileURL: url))
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
