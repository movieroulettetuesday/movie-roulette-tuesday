import XCTest

/// Deep links the new intents route through. Siri itself isn't available here;
/// this checks the app stays up and a movie link opens that movie.
final class AppIntentsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-MRTNoSplash", "-MRTMockCommunity", "-MRTUITest"]
        app.launch()
    }

    func testMovieEpisodeAndSpinRoutesStayInTheApp() {
        app.open(URL(string: "mrt://movie/the-devils-rain-1975")!)
        let title = app.descendants(matching: .any).matching(identifier: "movie-page-title").firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "The Devil's Rain")

        app.open(URL(string: "mrt://episode/Buzzsprout-20099500")!)
        XCTAssertEqual(app.state, .runningForeground)

        app.open(URL(string: "mrt://spin")!)
        // No pending spin payload: the route only has to leave the wheel on screen.
        let wheel = app.descendants(matching: .any)["Roulette wheel"]
        XCTAssertTrue(wheel.waitForExistence(timeout: 8))
        XCTAssertEqual(app.state, .runningForeground)
    }
}
