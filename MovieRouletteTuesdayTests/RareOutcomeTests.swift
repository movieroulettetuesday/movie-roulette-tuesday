import XCTest
@testable import MovieRouletteTuesday
import MRTCore

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
        let catalog = MovieCatalog(categories: [landed, other], movies: [
            Movie(id: "a", title: "A", year: 2000, genre: "G", categories: ["c1"]),
            Movie(id: "bad", title: "Bad", year: 2003, genre: "G", categories: ["c2"], isInfamous: true),
        ])
        var rng = SeededRandomNumberGenerator(seed: 1)
        let pick = RareOutcomeRoller.jackpotPick(in: catalog, landed: landed, using: &rng)
        XCTAssertEqual(pick?.movie.id, "bad")
        XCTAssertEqual(pick?.category.id, "c2")
        let none = MovieCatalog(categories: [landed], movies: [catalog.movies[0]])
        XCTAssertNil(RareOutcomeRoller.jackpotPick(in: none, landed: landed, using: &rng))
    }
}
