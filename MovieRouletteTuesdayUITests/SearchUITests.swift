import XCTest

/// 1.1 search on the Movies and Episodes lists (iPhone and iPad). The shared
/// matcher's rules are unit-tested in CatalogSearchTests; this checks the
/// fields, results, empty states, and opening a result.
final class SearchUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        if UIDevice.current.userInterfaceIdiom == .pad {
            // Landscape keeps the split view's sidebar (and its search field) on screen.
            XCUIDevice.shared.orientation = .landscapeLeft
        }
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
    }

    private func launch(tab: String, extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-MRTNoSplash", "-MRTMockCommunity", "-MRTUITest", "-MRTStartTab", tab] + extra
        app.launch()
    }

    private func searchField() -> XCUIElement {
        let field = app.searchFields.firstMatch
        if !field.waitForExistence(timeout: 8) || !field.isHittable {
            // The bar can start tucked under the title; pull the list down.
            app.swipeDown()
        }
        XCTAssertTrue(field.waitForExistence(timeout: 10), "search field")
        return field
    }

    /// Replaces the field's text.
    private func type(_ text: String, into field: XCUIElement) {
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 24))
        field.typeText(text)
    }

    /// Submits the search, as a user would to read results under a full-height
    /// keyboard (iPad landscape at AXXXL), then hides the keyboard if it stays.
    private func dismissKeyboard() {
        app.typeText("\n")
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists {
            let hide = keyboard.buttons["Hide keyboard"]
            if hide.exists { hide.tap() }
        }
        _ = keyboard.waitForNonExistence(timeout: 3)
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testMoviesSearchFindsApostropheTitleShowsEmptyStateAndOpensResult() {
        launch(tab: "movies")
        let field = searchField()
        type("zzqx", into: field)
        XCTAssertTrue(app.descendants(matching: .any)["movies-search-empty"].waitForExistence(timeout: 5),
                      "no-match empty state")
        attach("movies-search-empty")

        type("devils rain", into: field)
        let row = app.descendants(matching: .any)["movie-row-the-devils-rain-1975"]
        XCTAssertTrue(row.waitForExistence(timeout: 8), "“devils rain” finds The Devil's Rain")
        let count = app.staticTexts["movies-count"]
        if count.waitForExistence(timeout: 3) {
            XCTAssertTrue(count.label.hasPrefix("1 of "), count.label)
        }
        attach("movies-search-devils-rain")

        row.tap()
        let title = app.descendants(matching: .any).matching(identifier: "movie-page-title").firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10), "the result opens its movie page")
        XCTAssertEqual(title.label, "The Devil's Rain")
    }

    func testEpisodesSearchFindsSeasonEpisodeAndOpensIt() {
        launch(tab: "episodes")
        // The feed loads from the on-device cache or the network.
        XCTAssertTrue(app.descendants(matching: .any)["episode-row"].firstMatch.waitForExistence(timeout: 45),
                      "episodes loaded")
        let field = searchField()
        type("S4E39", into: field)
        let header = app.descendants(matching: .any)["episodes-search-count"]
        XCTAssertTrue(header.waitForExistence(timeout: 8), "results header")
        XCTAssertEqual(header.label, "1 result")
        let hit = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Devil")).firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: 5), "S4E39 is The Devil's Rain")
        attach("episodes-search-s4e39")

        app.descendants(matching: .any)["episode-row"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Devil")).firstMatch.waitForExistence(timeout: 8))
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testMoviesSearchAtLargestDynamicTypeSize() {
        launch(tab: "movies", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let field = searchField()
        type("the thing 1982", into: field)
        let row = app.descendants(matching: .any)["movie-row-the-thing-1982"]
        XCTAssertTrue(row.waitForExistence(timeout: 8), "year disambiguates at AXXXL")
        dismissKeyboard()
        XCTAssertTrue(row.isHittable, "result row is reachable at AXXXL")
        attach("movies-search-axxxl")
    }
}
