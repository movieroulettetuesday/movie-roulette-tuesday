import XCTest
@testable import MovieRouletteTuesday

final class RareOutcomeTests: XCTestCase {
    private let policy = RareOutcomePolicy.default

    func testBandsAtOnePercentEach() {
        XCTAssertEqual(RareOutcomeRoller.outcome(unitValue: 0, policy: policy, infamousAvailable: true), .forcedRespin)
        XCTAssertEqual(RareOutcomeRoller.outcome(unitValue: 0.0099, policy: policy, infamousAvailable: true), .forcedRespin)
        XCTAssertEqual(RareOutcomeRoller.outcome(unitValue: 0.01, policy: policy, infamousAvailable: true), .infamousJackpot)
        XCTAssertEqual(RareOutcomeRoller.outcome(unitValue: 0.0199, policy: policy, infamousAvailable: true), .infamousJackpot)
        XCTAssertEqual(RareOutcomeRoller.outcome(unitValue: 0.02, policy: policy, infamousAvailable: true), .normal)
        XCTAssertEqual(RareOutcomeRoller.outcome(unitValue: 0.9999, policy: policy, infamousAvailable: true), .normal)
    }

    func testJackpotFallsBackWithoutInfamousMovies() {
        XCTAssertEqual(RareOutcomeRoller.outcome(unitValue: 0.015, policy: policy, infamousAvailable: false), .normal)
    }

    func testRespinsNeverChain() {
        XCTAssertEqual(RareOutcomeRoller.outcome(unitValue: 0.001, policy: policy, infamousAvailable: true, allowRespin: false), .normal)
    }

    func testDisabledAndBadInput() {
        XCTAssertEqual(RareOutcomeRoller.outcome(unitValue: 0.001, policy: .disabled, infamousAvailable: true), .normal)
        XCTAssertEqual(RareOutcomeRoller.outcome(unitValue: .nan, policy: policy, infamousAvailable: true), .normal)
        let clamped = RareOutcomePolicy(forcedRespinChance: 0.8, infamousJackpotChance: 0.8)
        XCTAssertEqual(clamped.forcedRespinChance + clamped.infamousJackpotChance, 1, accuracy: 1e-12)
    }

    func testSeededFrequenciesAreRoughlyOnePercent() {
        var rng = SeededRandomNumberGenerator(seed: 42)
        var counts: [RareOutcome: Int] = [:]
        let n = 100_000
        for _ in 0..<n {
            counts[RareOutcomeRoller.roll(policy: policy, infamousAvailable: true, using: &rng), default: 0] += 1
        }
        XCTAssertEqual(Double(counts[.forcedRespin, default: 0]) / Double(n), 0.01, accuracy: 0.002)
        XCTAssertEqual(Double(counts[.infamousJackpot, default: 0]) / Double(n), 0.01, accuracy: 0.002)
    }

    func testRollIsDeterministicForSeed() {
        var a = SeededRandomNumberGenerator(seed: 7), b = SeededRandomNumberGenerator(seed: 7)
        let x = (0..<500).map { _ in RareOutcomeRoller.roll(policy: policy, infamousAvailable: true, using: &a) }
        let y = (0..<500).map { _ in RareOutcomeRoller.roll(policy: policy, infamousAvailable: true, using: &b) }
        XCTAssertEqual(x, y)
    }

    func testJackpotPick() {
        let landed = RouletteCategory(id: "c1", name: "C1", colorHex: "#000000", movieIds: ["a"])
        let other = RouletteCategory(id: "c2", name: "C2", colorHex: "#FFFFFF", movieIds: ["bad"])
        let a = Movie(id: "a", title: "A", year: 2000, genre: "G", categories: ["c1"])
        let bad = Movie(id: "bad", title: "Bad", year: 2003, genre: "G", categories: ["c2"])
        var rng = SeededRandomNumberGenerator(seed: 1)
        // A movie outside the landed category is shown under its own category.
        let onlyBad = MovieCatalog(categories: [landed, other], movies: [bad])
        let pick = RareOutcomeRoller.jackpotPick(in: onlyBad, landed: landed, using: &rng)
        XCTAssertEqual(pick?.movie.id, "bad")
        XCTAssertEqual(pick?.category.id, "c2")
        // 1.0.1: every movie is a jackpot candidate.
        let onlyA = MovieCatalog(categories: [landed, other], movies: [a])
        let pickA = RareOutcomeRoller.jackpotPick(in: onlyA, landed: landed, using: &rng)
        XCTAssertEqual(pickA?.movie.id, "a")
        XCTAssertEqual(pickA?.category.id, "c1")
        let empty = MovieCatalog(categories: [landed], movies: [])
        XCTAssertNil(RareOutcomeRoller.jackpotPick(in: empty, landed: landed, using: &rng))
    }

    func testJackpotAvailableForAnyCatalogMovie() {
        let landed = RouletteCategory(id: "c1", name: "C1", colorHex: "#000000", movieIds: ["a"])
        let catalog = MovieCatalog(categories: [landed], movies: [
            Movie(id: "a", title: "A", year: 2000, genre: "G", categories: ["c1"]),
        ])
        XCTAssertFalse(RareOutcomeRoller.jackpotCandidates(in: catalog).isEmpty)
        let alwaysJackpot = RareOutcomePolicy(isEnabled: true, forcedRespinChance: 0, infamousJackpotChance: 1)
        var rng = SeededRandomNumberGenerator(seed: 3)
        let out = QuickSpin.resolve(catalog: catalog, history: [], rareOutcomes: alwaysJackpot, using: &rng)
        XCTAssertEqual(out?.isJackpot, true)
        XCTAssertEqual(out?.movie.id, "a")
    }

    func testJackpotPickUsesListenerAverages() {
        let landed = RouletteCategory(id: "c1", name: "C1", colorHex: "#000000", movieIds: ["low", "high"])
        let catalog = MovieCatalog(categories: [landed], movies: [
            Movie(id: "low", title: "Low", year: 2000, genre: "G", categories: ["c1"]),
            Movie(id: "high", title: "High", year: 2000, genre: "G", categories: ["c1"]),
        ])
        var rng = SeededRandomNumberGenerator(seed: 11)
        var low = 0
        let n = 20_000
        for _ in 0..<n {
            let pick = RareOutcomeRoller.jackpotPick(in: catalog, landed: landed,
                                                     listenerAverages: ["low": 1, "high": 5], using: &rng)
            if pick?.movie.id == "low" { low += 1 }
        }
        // 4.5 / (4.5 + 0.5) = 0.9
        XCTAssertEqual(Double(low) / Double(n), 0.9, accuracy: 0.01)
    }
}

final class InfamousSelectionTests: XCTestCase {
    private func movies(_ count: Int) -> [Movie] {
        (0..<count).map { Movie(id: "m\($0)", title: "M\($0)", year: 2000, genre: "G") }
    }

    func testWeightingOrder() {
        let stars: [Double] = [0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5]
        let w = stars.map { InfamousSelection.weight(averageStars: $0) }
        XCTAssertEqual(w, [5, 4.5, 4, 3.5, 3, 2.5, 2, 1.5, 1, 0.5])
        for i in 1..<w.count { XCTAssertGreaterThan(w[i - 1], w[i], "lower rating must weigh more") }
        XCTAssertEqual(InfamousSelection.weight(averageStars: 1) / InfamousSelection.weight(averageStars: 5), 9)
    }

    func testUnratedGetsMiddleWeight() {
        let three = InfamousSelection.weight(averageStars: 3)
        XCTAssertEqual(three, 2.5)
        XCTAssertEqual(InfamousSelection.unratedWeight, three)
        XCTAssertEqual(InfamousSelection.weight(averageStars: nil), three)
        XCTAssertEqual(InfamousSelection.weight(averageStars: .nan), three)
        XCTAssertEqual(InfamousSelection.weight(averageStars: .infinity), three)
        let m = movies(2)
        XCTAssertEqual(InfamousSelection.weights(for: m, averages: ["m1": 1]), [2.5, 4.5])
    }

    func testWeightsAlwaysPositiveAndClamped() {
        XCTAssertEqual(InfamousSelection.weight(averageStars: 0), 5)
        XCTAssertEqual(InfamousSelection.weight(averageStars: -3), 5)
        XCTAssertEqual(InfamousSelection.weight(averageStars: 7), 0.5)
        for half in -4...14 {
            let w = InfamousSelection.weight(averageStars: Double(half) / 2)
            XCTAssertTrue(w.isFinite && w > 0)
        }
    }

    func testWeightIsPurelyListenerRating() {
        let m = movies(3)
        let w = InfamousSelection.weights(for: m, averages: ["m0": 0.5, "m1": 3, "m2": 5])
        XCTAssertEqual(w, [5, 2.5, 0.5])
        XCTAssertEqual(InfamousSelection.maxWeight, 5)
        let landed = RouletteCategory(id: "c", name: "C", colorHex: "#000000")
        let catalog = MovieCatalog(categories: [landed], movies: m)
        XCTAssertEqual(RareOutcomeRoller.jackpotCandidates(in: catalog), m)
    }

    /// 1.0.1: a legacy `"isInfamous": true` in the catalog JSON is ignored, so
    /// a 5-star flagged movie weighs 0.5 (not 5.0) and an unrated one 2.5.
    func testLegacyInfamousFlagInCatalogIsIgnored() async throws {
        let json = """
        {"categories":[{"id":"c","name":"C","colorHex":"#123456","movieIds":["a","b"]}],
         "movies":[{"id":"a","title":"A","year":1999,"genre":"Drama","isInfamous":true},
                   {"id":"b","title":"B","year":2000,"genre":"Drama","isInfamous":true}]}
        """
        let catalog = try await DataCatalogSource(data: Data(json.utf8)).loadCatalog()
        XCTAssertEqual(InfamousSelection.weights(for: catalog.movies, averages: ["a": 5]), [0.5, 2.5])
        XCTAssertEqual(InfamousSelection.probabilities(for: catalog.movies, averages: ["a": 5]), [0.5 / 3, 2.5 / 3])
    }

    /// Test vectors (also in infamous-selection.md for the Android port).
    func testProbabilityVectors() {
        func p(_ avgs: [Double?]) -> [Double] {
            let m = movies(avgs.count)
            var a: [String: Double] = [:]
            for (i, v) in avgs.enumerated() { if let v { a["m\(i)"] = v } }
            return InfamousSelection.probabilities(for: m, averages: a)
        }
        func eq(_ x: [Double], _ y: [Double], file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertEqual(x.count, y.count, file: file, line: line)
            for (a, b) in zip(x, y) { XCTAssertEqual(a, b, accuracy: 1e-12, file: file, line: line) }
        }
        eq(p([1, 5]), [0.9, 0.1])
        eq(p([1, 3, 5, nil]), [0.45, 0.25, 0.05, 0.25])
        eq(p([nil, nil, nil, nil]), [0.25, 0.25, 0.25, 0.25])
        eq(p([0.5, 2.5, 4.5]), [5 / 9.0, 3 / 9.0, 1 / 9.0])
        eq(p([5, 2, nil]), [0.5 / 6.5, 3.5 / 6.5, 2.5 / 6.5])
    }

    func testSeededDistributionMatchesWeights() {
        let m = movies(4)
        let averages: [String: Double] = ["m0": 1, "m1": 3, "m2": 5] // m3 unrated
        var rng = SeededRandomNumberGenerator(seed: 42)
        var counts = [Int](repeating: 0, count: 4)
        let n = 100_000
        for _ in 0..<n {
            let pick = InfamousSelection.pick(from: m, averages: averages, using: &rng)!
            counts[m.firstIndex(of: pick)!] += 1
        }
        let expected = [0.45, 0.25, 0.05, 0.25]
        for i in 0..<4 { XCTAssertEqual(Double(counts[i]) / Double(n), expected[i], accuracy: 0.006) }
        XCTAssertGreaterThan(counts[0], counts[1])
        XCTAssertGreaterThan(counts[1], counts[2])
    }

    func testDeterministicForSeed() {
        let m = movies(10)
        let averages: [String: Double] = ["m0": 1, "m3": 4.5, "m7": 2]
        var a = SeededRandomNumberGenerator(seed: 99), b = SeededRandomNumberGenerator(seed: 99)
        let x = (0..<300).map { _ in InfamousSelection.pick(from: m, averages: averages, using: &a)!.id }
        let y = (0..<300).map { _ in InfamousSelection.pick(from: m, averages: averages, using: &b)!.id }
        XCTAssertEqual(x, y)
    }

    func testEmptyCatalog() {
        var rng = SeededRandomNumberGenerator(seed: 1)
        XCTAssertNil(InfamousSelection.pick(from: [], averages: ["x": 1], using: &rng))
        XCTAssertEqual(InfamousSelection.probabilities(for: [], averages: [:]), [])
        XCTAssertNil(InfamousSelection.pickIndex(for: [], averages: [:], unitValue: 0.5))
    }

    func testAllUnratedIsUniform() {
        let m = movies(5)
        XCTAssertEqual(InfamousSelection.weights(for: m, averages: [:]), [2.5, 2.5, 2.5, 2.5, 2.5])
        var rng = SeededRandomNumberGenerator(seed: 5)
        var counts = [String: Int]()
        let n = 50_000
        for _ in 0..<n { counts[InfamousSelection.pick(from: m, averages: [:], using: &rng)!.id, default: 0] += 1 }
        XCTAssertEqual(counts.count, 5)
        for c in counts.values { XCTAssertEqual(Double(c) / Double(n), 0.2, accuracy: 0.01) }
    }

    func testNeverNilWhenMoviesExist() {
        var gen = SeededRandomNumberGenerator(seed: 2026)
        let odd: [Double] = [.nan, .infinity, -.infinity, -1, 0, 0.5, 3, 5, 9]
        for _ in 0..<500 {
            let count = Int.random(in: 1...20, using: &gen)
            let m = movies(count)
            var averages: [String: Double] = [:]
            for movie in m where Bool.random(using: &gen) { averages[movie.id] = odd.randomElement(using: &gen)! }
            let pick = InfamousSelection.pick(from: m, averages: averages, using: &gen)
            XCTAssertNotNil(pick)
            XCTAssertTrue(m.contains(pick!))
            for unit in [0, 0.5, 0.999_999_999, 1, .nan, -1, 2] {
                XCTAssertNotNil(InfamousSelection.pickIndex(for: m, averages: averages, unitValue: unit))
            }
        }
    }
}
