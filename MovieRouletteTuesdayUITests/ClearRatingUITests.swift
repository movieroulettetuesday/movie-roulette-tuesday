import XCTest

/// Clears a seeded 3½-star rating and a ½-star rating from the movie page,
/// then relaunches without the seed. Uses the button and star row, not VoiceOver.
/// iCloud delete is not covered: `-MRTMockCommunity` keeps the listener store in memory.
final class ClearRatingUITests: XCTestCase {
    private let ratedMovie = "a-face-in-the-crowd-1957"
    private let watchlistMovie = "deadly-games-1989"
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testClearThreeAndAHalfThenHalfStarPersistsAndKeepsWatchState() {
        launchSeeded(halfStars: 7)
        XCTAssertEqual(ratingValue(), "3.5 of 5 stars")
        let clear = app.buttons["clear-rating"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        XCTAssertEqual(clear.label, "Clear rating")
        assertWatchedStaysSelected()
        let spins = spinLabel()

        clear.tap()
        XCTAssertEqual(waitForRatingValue("Not rated"), "Not rated")
        XCTAssertFalse(app.buttons["clear-rating"].exists)
        assertWatchedStaysSelected()
        XCTAssertEqual(spinLabel(), spins)

        launchPersistedMovie()
        XCTAssertEqual(ratingValue(), "Not rated")
        XCTAssertFalse(app.buttons["clear-rating"].exists)
        assertWatchedStaysSelected()

        rate(step: 1)
        XCTAssertEqual(waitForRatingValue("0.5 of 5 stars"), "0.5 of 5 stars")
        XCTAssertTrue(app.buttons["clear-rating"].waitForExistence(timeout: 5))
        app.buttons["clear-rating"].tap()
        XCTAssertEqual(waitForRatingValue("Not rated"), "Not rated")

        launchPersistedMovie()
        XCTAssertEqual(ratingValue(), "Not rated")
        rate(step: 7)
        XCTAssertEqual(waitForRatingValue("3.5 of 5 stars"), "3.5 of 5 stars")

        launchMovies()
        search("Deadly Games")
        let watchlist = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "On your watchlist")
        ).firstMatch
        XCTAssertTrue(watchlist.waitForExistence(timeout: 5), "watchlist movie stays after the other movie is cleared")
    }

    private func launchSeeded(halfStars: Int) {
        app.launchArguments = [
            "-MRTUITest", "-MRTNoSplash", "-MRTMockCommunity",
            "-MRTOpenMovie", ratedMovie,
            "-MRTSeedRating", ratedMovie, "\(halfStars)",
            "-MRTSeedWatchlist", watchlistMovie,
        ]
        app.launch()
    }

    /// No `-MRTUITest` and no seed: the ratings file from the previous launch is what Clear wrote.
    private func launchPersistedMovie() {
        app.terminate()
        app.launchArguments = ["-MRTNoSplash", "-MRTMockCommunity", "-MRTOpenMovie", ratedMovie]
        app.launch()
    }

    private func launchMovies() {
        app.terminate()
        app.launchArguments = ["-MRTNoSplash", "-MRTMockCommunity", "-MRTStartTab", "movies"]
        app.launch()
    }

    private func ratingElement() -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Rating")).firstMatch
    }

    private func ratingValue() -> String {
        let element = ratingElement()
        XCTAssertTrue(element.waitForExistence(timeout: 25), "star row on the movie page")
        return element.value as? String ?? ""
    }

    private func waitForRatingValue(_ expected: String) -> String {
        let element = ratingElement()
        let matched = NSPredicate(format: "value == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: matched, object: element)
        _ = XCTWaiter().wait(for: [expectation], timeout: 5)
        return element.value as? String ?? ""
    }

    private func assertWatchedStaysSelected() {
        let status = app.segmentedControls["movie-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.buttons["Watched"].isSelected)
        XCTAssertFalse(status.buttons["Want to watch"].isSelected)
    }

    private func spinLabel() -> String? {
        let spin = app.descendants(matching: .any)["movie-spin-count"]
        return spin.exists ? spin.label : nil
    }

    /// Taps the half-step button. `coordinate(withNormalizedOffset:)` is not used:
    /// on a 3x iPhone the accessibility frame of this row is about one third of
    /// its point size, so a 5% coordinate lands off the stars.
    private func rate(step: Int) {
        let button = app.buttons["rating-step-\(step)"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "half-step \(step)")
        button.tap()
    }

    private func search(_ title: String) {
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        field.tap()
        field.typeText(title)
    }
}
