import XCTest

/// Episodes, Movies, Movie Page, Stats, Settings, and the Suggest QR card.
/// `-MRTStartTab`, `-MRTOpenMovie`, and `-MRTShowSuggest` open a screen directly
/// so the test doesn't have to walk the tab bar. `-MRTUITest` keeps the bundled catalog.
final class TVScreensUITests: XCTestCase {
    private var app: XCUIApplication!
    private var remote: XCUIRemote { XCUIRemote.shared }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-MRTUITest"]
    }

    private func launch(_ extra: [String] = []) {
        app.launchArguments += extra
        app.launch()
    }

    private func waitForFocus(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let focused = NSPredicate(format: "exists == true AND hasFocus == true")
        return XCTWaiter().wait(for: [expectation(for: focused, evaluatedWith: element)], timeout: timeout) == .completed
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testEpisodesScreen() {
        launch(["-MRTStartTab", "episodes"])
        let screen = app.descendants(matching: .any)["tv.screen.episodes"]
        XCTAssertTrue(screen.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Episodes"].exists)
        attach("tv-episodes")
    }

    func testMoviesSearchFiltersAndSort() {
        launch(["-MRTStartTab", "movies"])
        let search = app.descendants(matching: .any)["tv.movies.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 20), "search field on the Movies tab")
        XCTAssertTrue(app.descendants(matching: .any)["tv.movies.filter.all"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["tv.movies.filter.cat-horror"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["tv.movies.sort"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["tv.movies.summary"].exists)
        attach("tv-movies")
    }

    func testMoviePageWhereToWatchPollAndSuggest() {
        launch(["-MRTOpenMovie", "a-face-in-the-crowd-1957"])
        let title = app.descendants(matching: .any)["tv.movie.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        XCTAssertTrue(title.label.contains("Face"))
        let yearGenre = app.descendants(matching: .any)["tv.movie.yearGenre"]
        XCTAssertTrue(yearGenre.waitForExistence(timeout: 5))
        XCTAssertEqual(yearGenre.label, "1957 · Drama", "year is four digits, not a grouped number like 1,957")
        XCTAssertTrue(app.descendants(matching: .any)["tv.movie.whereToWatch"].exists)
        let stars = app.descendants(matching: .any)["tv.movie.stars"]
        let firstStar = app.descendants(matching: .any)["tv.movie.star.1"]
        XCTAssertTrue(stars.exists || firstStar.exists, "rating stars")
        XCTAssertTrue(app.descendants(matching: .any)["tv.movie.watchlist"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["tv.movie.poll"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["tv.movie.suggest"].exists)
        XCTAssertTrue(app.buttons["tv.back"].exists)
        XCTAssertFalse(app.staticTexts["Roulette"].exists && app.buttons["tv.spin"].exists,
                       "the movie page hides the Roulette tab")
        attach("tv-movie-page")
    }

    func testStatsOpensSettings() {
        launch(["-MRTStartTab", "stats"])
        let settings = app.buttons["tv.stats.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Stats"].exists)
        if !waitForFocus(settings, timeout: 8) {
            remote.press(.down) // leave the tab bar for the Stats content
        }
        XCTAssertTrue(waitForFocus(settings), "Settings has focus")
        remote.press(.select)
        XCTAssertTrue(app.descendants(matching: .any)["tv.screen.settings"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["tv.settings.spinSound"].exists)
        XCTAssertTrue(app.buttons["tv.settings.apple"].exists)
        XCTAssertTrue(app.buttons["tv.settings.spotify"].exists)
        XCTAssertTrue(app.buttons["tv.settings.suggest"].exists)
        attach("tv-settings")
    }

    func testSuggestQR() {
        launch(["-MRTShowSuggest"])
        XCTAssertTrue(app.descendants(matching: .any)["tv.screen.suggest"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["tv.suggest.qr"].exists)
        XCTAssertTrue(app.buttons["tv.suggest.done"].exists)
        let url = app.staticTexts["tv.suggest.url"]
        XCTAssertTrue(url.waitForExistence(timeout: 5))
        XCTAssertTrue(url.label.contains("buzzsprout.com"))
        XCTAssertTrue(url.label.contains("fan_mail"))
        attach("tv-suggest-qr")
    }
}
