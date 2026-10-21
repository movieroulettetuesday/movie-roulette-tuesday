import XCTest
@testable import MovieRouletteTuesday
import MRTCore

final class WidgetSupportTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private let catalog = MovieCatalog(
        categories: [
            RouletteCategory(id: "a", name: "A", colorHex: "#111111", movieIds: ["m1", "m2"]),
            RouletteCategory(id: "b", name: "B", colorHex: "#222222", movieIds: ["m3"]),
            RouletteCategory(id: "empty", name: "Empty", colorHex: "#333333")
        ],
        movies: [
            Movie(id: "m1", title: "One", year: 2000, genre: "G", categories: ["a"]),
            Movie(id: "m2", title: "Two", year: 2001, genre: "G", categories: ["a"]),
            Movie(id: "m3", title: "Three", year: 2002, genre: "G", categories: ["b"])
        ]
    )

    func testStableHashKnownValues() {
        XCTAssertEqual(SpinOfTheDay.stableHash(""), 0xcbf2_9ce4_8422_2325)
        XCTAssertEqual(SpinOfTheDay.stableHash("a"), 0xaf63_dc4c_8601_ec8c)
    }

    func testDayKey() {
        let date = Date(timeIntervalSince1970: 1_791_460_800) // 2026-10-08 12:00 UTC
        XCTAssertEqual(SpinOfTheDay.dayKey(for: date, calendar: utc), "2026-10-08")
    }

    func testSameDaySamePickAndValidMembership() throws {
        let morning = Date(timeIntervalSince1970: 1_791_417_600 + 60)       // 00:01 UTC
        let night = Date(timeIntervalSince1970: 1_791_417_600 + 86_340)     // 23:59 UTC
        let a = try XCTUnwrap(SpinOfTheDay.pick(for: morning, in: catalog, calendar: utc))
        let b = try XCTUnwrap(SpinOfTheDay.pick(for: night, in: catalog, calendar: utc))
        XCTAssertEqual(a, b)
        if let category = a.category, category.id != "empty" {
            XCTAssertTrue(category.movieIds.contains(a.movie.id))
        }
    }

    func testPickVariesAcrossDays() {
        let start = Date(timeIntervalSince1970: 1_791_460_800)
        let ids = Set((0..<60).compactMap {
            SpinOfTheDay.pick(for: start.addingTimeInterval(Double($0) * 86_400), in: catalog, calendar: utc)?.movie.id
        })
        XCTAssertEqual(ids, ["m1", "m2", "m3"])
    }

    func testEmptyCatalogGivesNil() {
        XCTAssertNil(SpinOfTheDay.pick(for: Date(), in: MovieCatalog(categories: [], movies: [])))
    }

    func testNextRefreshIsNextMidnight() {
        let date = Date(timeIntervalSince1970: 1_791_460_800)
        XCTAssertEqual(SpinOfTheDay.nextRefresh(after: date, calendar: utc),
                       Date(timeIntervalSince1970: 1_791_504_000))
    }

    func testLatestEpisodeByDate() {
        let older = PodcastEpisode(guid: "1", title: "Old", pubDate: Date(timeIntervalSince1970: 100))
        let newer = PodcastEpisode(guid: "2", title: "New", pubDate: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(WidgetSnapshot.latest(in: [older, newer])?.guid, "2")
        XCTAssertNil(WidgetSnapshot.latest(in: []))
    }

    func testSnapshotStoreRoundTripAndChangeDetection() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = WidgetSnapshotStore(fileURL: dir.appendingPathComponent(WidgetSnapshotStore.fileName))
        XCTAssertNil(store.load())

        let episode = WidgetSnapshot.EpisodeInfo(guid: "Buzzsprout-1", title: "The Outsiders", season: 4, episode: 34)
        XCTAssertTrue(try store.update { $0.latestEpisode = episode })
        XCTAssertEqual(store.load()?.latestEpisode, episode)
        XCTAssertEqual(store.load()?.latestEpisode?.seasonEpisodeLabel, "S4E34")
        XCTAssertFalse(try store.update { $0.latestEpisode = episode }, "unchanged data should not rewrite")

        let spin = WidgetSnapshot.SpinInfo(movieId: "m1", title: "One", year: 2000, categoryName: "A",
                                           colorHex: "#111111", timestamp: Date(timeIntervalSince1970: 5))
        XCTAssertTrue(try store.update { $0.lastSpin = spin })
        XCTAssertEqual(store.load()?.latestEpisode, episode, "updates merge, not replace")
        XCTAssertEqual(store.load()?.lastSpin, spin)

        try Data("junk".utf8).write(to: store.fileURL)
        XCTAssertNil(store.load())
    }
}
