import XCTest
@testable import MovieRouletteTuesday
import MRTCore

final class QuickSpinTests: XCTestCase {
    private var moviesURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MovieRouletteTuesday/Resources/movies.json")
    }

    func testQuickSpinPicksAMovieFromTheLandedCategory() async throws {
        guard FileManager.default.fileExists(atPath: moviesURL.path) else { throw XCTSkip("no movies.json") }
        let catalog = try await FileCatalogSource(fileURL: moviesURL).loadCatalog().deduplicated()
        var rng = SeededRandomNumberGenerator(seed: 42)
        var landedIDs = Set<String>()
        for _ in 0..<200 {
            let out = try XCTUnwrap(QuickSpin.resolve(catalog: catalog, history: [], rareOutcomes: .disabled, using: &rng))
            XCTAssertFalse(out.isJackpot)
            XCTAssertEqual(out.category, out.landed)
            XCTAssertTrue(catalog.categories.contains(out.landed))
            XCTAssertTrue(catalog.movies.contains(out.movie))
            landedIDs.insert(out.landed.id)
        }
        XCTAssertEqual(landedIDs.count, catalog.categories.count, "every slice reachable")
    }

    func testQuickSpinForcedRespinNeverChains() async throws {
        guard FileManager.default.fileExists(atPath: moviesURL.path) else { throw XCTSkip("no movies.json") }
        let catalog = try await FileCatalogSource(fileURL: moviesURL).loadCatalog().deduplicated()
        var rng = SeededRandomNumberGenerator(seed: 7)
        let always = RareOutcomePolicy(isEnabled: true, forcedRespinChance: 1, infamousJackpotChance: 0)
        let out = try XCTUnwrap(QuickSpin.resolve(catalog: catalog, history: [], rareOutcomes: always, using: &rng))
        XCTAssertTrue(out.wasForcedRespin)
        let empty = MovieCatalog(schemaVersion: 1, show: nil, categories: [], movies: [])
        XCTAssertNil(QuickSpin.resolve(catalog: empty, history: [], rareOutcomes: .disabled, using: &rng))
    }
}
