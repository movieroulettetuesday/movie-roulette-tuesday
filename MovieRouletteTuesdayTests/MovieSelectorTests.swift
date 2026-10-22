import XCTest
@testable import MovieRouletteTuesday
import MRTCore

final class MovieSelectorTests: XCTestCase {
    private let category = RouletteCategory(id: "cat", name: "Cat", colorHex: "#FF0000", movieIds: ["a", "b", "ghost"])
    private lazy var catalog = MovieCatalog(
        categories: [category, RouletteCategory(id: "empty", name: "Empty", colorHex: "#000000")],
        movies: [
            Movie(id: "a", title: "A", year: 2000, genre: "G", categories: ["cat"]),
            Movie(id: "b", title: "B", year: 2000, genre: "G", categories: ["cat"]),
            // Only tagged on the movie side; still a candidate.
            Movie(id: "c", title: "C", year: 2000, genre: "G", categories: ["cat"]),
            Movie(id: "d", title: "D", year: 2000, genre: "G", categories: ["cat"]),
            Movie(id: "z", title: "Z", year: 2000, genre: "G", categories: ["other"])
        ]
    )
    private let selector = MovieSelector()

    private func history(_ ids: String...) -> [SpinResult] {
        ids.enumerated().map { SpinResult(movieId: $1, categoryId: "cat", timestamp: Date(timeIntervalSince1970: Double($0))) }
    }

    func testCandidatesUnionCategoryListAndMovieTagsWithoutDuplicates() {
        XCTAssertEqual(selector.candidates(for: category, in: catalog).map(\.id), ["a", "b", "c", "d"])
    }

    func testWeights() {
        let a = catalog.movie(withId: "a")!
        let d = catalog.movie(withId: "d")!
        XCTAssertEqual(selector.weight(for: a, history: []), 1)
        // 1.0.1: no infamous boost; every movie starts at weight 1.
        XCTAssertEqual(selector.weight(for: d, history: []), 1)
        XCTAssertEqual(selector.weight(for: a, history: history("a")), 0.1, accuracy: 1e-12)
        // Two spins ago, window 5: 0.1 + 0.9 * 1/5
        XCTAssertEqual(selector.weight(for: a, history: history("a", "b")), 0.28, accuracy: 1e-12)
        // Five spins ago is still in the window; six is not.
        XCTAssertEqual(selector.weight(for: a, history: history("a", "b", "b", "b", "b")), 0.82, accuracy: 1e-12)
        XCTAssertEqual(selector.weight(for: a, history: history("a", "b", "b", "b", "b", "b")), 1)
        // The most recent occurrence wins.
        XCTAssertEqual(selector.weight(for: a, history: history("a", "b", "a")), 0.1, accuracy: 1e-12)
        XCTAssertEqual(selector.weight(for: d, history: history("d")), 0.1, accuracy: 1e-12)
    }

    func testRecencyMultiplierShape() {
        XCTAssertEqual(selector.recencyMultiplier(spinsAgo: nil), 1)
        XCTAssertEqual(selector.recencyMultiplier(spinsAgo: 0), 1)
        XCTAssertEqual(selector.recencyMultiplier(spinsAgo: 6), 1)
        let values = (1...5).map { selector.recencyMultiplier(spinsAgo: $0) }
        XCTAssertEqual(values, values.sorted())
        XCTAssertTrue(values.allSatisfy { $0 > 0 && $0 < 1 })
    }

    func testPickIndexExactIntervals() {
        let weights: [Double] = [1, 2, 1]
        XCTAssertEqual(MovieSelector.pickIndex(weights: weights, unitValue: 0), 0)
        XCTAssertEqual(MovieSelector.pickIndex(weights: weights, unitValue: 0.2499), 0)
        XCTAssertEqual(MovieSelector.pickIndex(weights: weights, unitValue: 0.25), 1)
        XCTAssertEqual(MovieSelector.pickIndex(weights: weights, unitValue: 0.7499), 1)
        XCTAssertEqual(MovieSelector.pickIndex(weights: weights, unitValue: 0.75), 2)
        XCTAssertEqual(MovieSelector.pickIndex(weights: weights, unitValue: 0.99999), 2)
        XCTAssertEqual(MovieSelector.pickIndex(weights: weights, unitValue: 1), 2)
        XCTAssertEqual(MovieSelector.pickIndex(weights: weights, unitValue: -5), 0)
    }

    func testPickIndexEdgeCases() {
        XCTAssertNil(MovieSelector.pickIndex(weights: [], unitValue: 0.5))
        XCTAssertEqual(MovieSelector.pickIndex(weights: [0, 1, 0], unitValue: 0), 1)
        XCTAssertEqual(MovieSelector.pickIndex(weights: [0, 1, 0], unitValue: 0.999), 1)
        XCTAssertEqual(MovieSelector.pickIndex(weights: [.nan, -1, 3], unitValue: 0.1), 2)
        // Nothing usable -> uniform fallback.
        XCTAssertEqual(MovieSelector.pickIndex(weights: [0, 0, 0, 0], unitValue: 0.6), 2)
    }

    func testDeterministicWithSeededGenerator() {
        func run(seed: UInt64) -> [String] {
            var rng = SeededRandomNumberGenerator(seed: seed)
            var log: [SpinResult] = []
            return (0..<50).map { _ in
                let movie = selector.selectMovie(from: category, in: catalog, history: log, using: &rng)!
                log.append(SpinResult(movieId: movie.id, categoryId: category.id))
                return movie.id
            }
        }
        XCTAssertEqual(run(seed: 1234), run(seed: 1234))
        XCTAssertNotEqual(run(seed: 1234), run(seed: 4321))
    }

    func testRecentlySpunMovieIsPickedLessOften() {
        var rng = SeededRandomNumberGenerator(seed: 8)
        let log = history("a") // weights: a 0.1, b 1, c 1, d 1 (total 3.1)
        var counts: [String: Int] = [:]
        for _ in 0..<20_000 {
            counts[selector.selectMovie(from: category, in: catalog, history: log, using: &rng)!.id, default: 0] += 1
        }
        let a = counts["a", default: 0], b = counts["b", default: 0], c = counts["c", default: 0], d = counts["d", default: 0]
        // Expected ~645 / 6452 / 6452 / 6452.
        XCTAssertTrue((450...850).contains(a), "a=\(a)")
        for (id, n) in [("b", b), ("c", c), ("d", d)] {
            XCTAssertTrue((6000...6900).contains(n), "\(id)=\(n)")
        }
    }

    func testOnlyRecentCandidateIsStillSelectable() {
        let solo = RouletteCategory(id: "solo", name: "Solo", colorHex: "#FFFFFF", movieIds: ["z"])
        var rng = SeededRandomNumberGenerator(seed: 3)
        let picked = selector.selectMovie(from: solo, in: catalog, history: history("z", "z"), using: &rng)
        XCTAssertEqual(picked?.id, "z")
    }

    func testEmptyCategoryReturnsNil() {
        var rng = SeededRandomNumberGenerator(seed: 3)
        XCTAssertNil(selector.selectMovie(from: catalog.categories[1], in: catalog, history: [], using: &rng))
    }

    func testAnyRandomNumberGeneratorForwardsToBase() {
        var erased = AnyRandomNumberGenerator(SeededRandomNumberGenerator(seed: 5))
        var plain = SeededRandomNumberGenerator(seed: 5)
        for _ in 0..<10 { XCTAssertEqual(erased.next(), plain.next()) }
    }
}
