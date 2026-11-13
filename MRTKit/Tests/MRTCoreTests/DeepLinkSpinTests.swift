import XCTest
@testable import MRTCore

final class DeepLinkSpinTests: XCTestCase {
    func testSpinAndEpisodesRoundTripAndDoNotCollideWithTopShelfRoutes() throws {
        XCTAssertEqual(DeepLink(url: try XCTUnwrap(URL(string: "mrt://spin"))), .spin)
        XCTAssertEqual(DeepLink(url: try XCTUnwrap(URL(string: "MRT://Spin"))), .spin)
        XCTAssertEqual(DeepLink(url: DeepLink.spin.url), .spin)
        XCTAssertEqual(DeepLink.spin.url.scheme, "mrt")
        XCTAssertEqual(DeepLink.spin.url.host, "spin")
        XCTAssertEqual(DeepLink.spin.url.path, "")

        XCTAssertEqual(DeepLink(url: try XCTUnwrap(URL(string: "mrt://episodes"))), .episodes)
        XCTAssertEqual(DeepLink(url: DeepLink.episodes.url), .episodes)

        // Top Shelf movie and episode links are unchanged.
        let movie = DeepLink.movie(id: "the-devils-rain-1975")
        XCTAssertEqual(DeepLink(url: movie.url), movie)
        let episode = DeepLink.episode(guid: "Buzzsprout-19913482")
        XCTAssertEqual(DeepLink(url: episode.url), episode)

        // Extra path on a bare wheel/episodes route is rejected.
        XCTAssertNil(DeepLink(url: try XCTUnwrap(URL(string: "mrt://spin/the-devils-rain-1975"))))
        XCTAssertNil(DeepLink(url: try XCTUnwrap(URL(string: "mrt://episodes/latest"))))
        // A movie whose id happens to be "spin" is still a movie, not the wheel route.
        XCTAssertEqual(DeepLink(url: try XCTUnwrap(URL(string: "mrt://movie/spin"))), .movie(id: "spin"))
        XCTAssertEqual(DeepLink(url: try XCTUnwrap(URL(string: "mrt://movie/spin-city-1996"))), .movie(id: "spin-city-1996"))
        XCTAssertNotEqual(DeepLink(url: try XCTUnwrap(URL(string: "mrt://movie/spin"))), .spin)
    }
}
