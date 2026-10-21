import XCTest
@testable import MovieRouletteTuesday
import MRTCore

final class SpinHistoryRoutingTests: XCTestCase {
    private let catalog = MovieCatalog(
        schemaVersion: 2,
        show: .mrt,
        categories: [RouletteCategory(id: "c", name: "C", colorHex: "#123456")],
        movies: [
            Movie(id: "two-eps", title: "Two Episodes", year: 2001, genre: "Drama", categories: ["c"],
                  episodeIds: ["Buzzsprout-old", "Buzzsprout-new"]),
            Movie(id: "no-eps", title: "Not Discussed", year: 2002, genre: "Drama", categories: ["c"]),
        ]
    )

    private func spin(_ movieId: String) -> SpinResult {
        SpinResult(movieId: movieId, categoryId: "c")
    }

    private func episode(_ guid: String) -> PodcastEpisode {
        PodcastEpisode(guid: guid, title: guid)
    }

    func testOpensFirstEpisodeThatIsInTheFeed() {
        let feed = ["Buzzsprout-old": episode("Buzzsprout-old"), "Buzzsprout-new": episode("Buzzsprout-new")]
        XCTAssertEqual(SpinHistoryRouting.destination(for: spin("two-eps"), catalog: catalog, episodesByGUID: feed),
                       .episode("Buzzsprout-old"))
        // First id not in the feed (yet): falls through to the next one.
        let partial = ["Buzzsprout-new": episode("Buzzsprout-new")]
        XCTAssertEqual(SpinHistoryRouting.destination(for: spin("two-eps"), catalog: catalog, episodesByGUID: partial),
                       .episode("Buzzsprout-new"))
    }

    func testFallsBackToMoviePage() {
        // Feed not loaded / episode missing.
        XCTAssertEqual(SpinHistoryRouting.destination(for: spin("two-eps"), catalog: catalog, episodesByGUID: [:]),
                       .movie("two-eps"))
        // Movie never discussed: movie page.
        XCTAssertEqual(SpinHistoryRouting.destination(for: spin("no-eps"), catalog: catalog,
                                                      episodesByGUID: ["Buzzsprout-old": episode("Buzzsprout-old")]),
                       .movie("no-eps"))
    }

    func testUnknownMovieOrNoCatalogIsNotTappable() {
        XCTAssertNil(SpinHistoryRouting.destination(for: spin("gone-from-catalog"), catalog: catalog, episodesByGUID: [:]))
        XCTAssertNil(SpinHistoryRouting.destination(for: spin("two-eps"), catalog: nil,
                                                    episodesByGUID: ["Buzzsprout-old": episode("Buzzsprout-old")]))
    }
}
