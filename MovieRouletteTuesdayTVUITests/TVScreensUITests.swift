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
        XCTAssertFalse(app.buttons["tv.movie.clearRating"].exists, "an unrated movie has no Clear rating button and is not a zero")
        XCTAssertTrue(app.descendants(matching: .any)["tv.movie.watchlist"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["tv.movie.poll"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["tv.movie.suggest"].exists)
        XCTAssertTrue(app.buttons["tv.back"].exists)
        XCTAssertFalse(app.staticTexts["Roulette"].exists && app.buttons["tv.spin"].exists,
                       "the movie page hides the Roulette tab")
        attach("tv-movie-page")
    }

    func testClearHalfStarAndThreePointFiveWithRemoteSelect() {
        clearSeeded(halfStars: 1, shown: "0.5 of 5 stars")
        clearSeeded(halfStars: 7, shown: "3.5 of 5 stars")
    }

    /// Focus and Select. The second launch omits `-MRTUITest`, so the wipe and
    /// seed do not run and the cleared rating has to still be gone.
    private func clearSeeded(halfStars: Int, shown: String) {
        let movie = "a-face-in-the-crowd-1957"
        app.launchArguments = [
            "-MRTUITest", "-MRTOpenMovie", movie,
            "-MRTSeedRating", movie, "\(halfStars)",
            "-MRTSeedWatchlist", movie,
        ]
        app.launch()
        let stars = app.descendants(matching: .any)["tv.movie.stars"]
        XCTAssertTrue(stars.waitForExistence(timeout: 20))
        XCTAssertEqual(stars.value as? String, shown)
        let watchlist = app.descendants(matching: .any)["tv.movie.watchlist"]
        XCTAssertEqual(watchlist.value as? String, "On")
        let clear = app.buttons["tv.movie.clearRating"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        XCTAssertEqual(clear.label, "Clear rating")
        let firstStar = app.buttons["tv.movie.star.1"]
        XCTAssertTrue(firstStar.waitForExistence(timeout: 5))
        // Your Rating is the left card, so star 1 shares x with the initial
        // provider. One Down must move. One Up must come back.
        guard let provider = waitForFocusedProvider() else {
            failFocus("No provider was focused before navigating to the rating")
            return
        }
        remote.press(.down)
        guard waitForFocus(firstStar, timeout: 2) else {
            failFocus("Down from \(provider.identifier) \(provider.frame) did not focus star 1 \(firstStar.frame). Star 1 must overlap that tile's x range.")
            return
        }
        remote.press(.up)
        guard waitForFocusedProvider(timeout: 2) != nil else {
            failFocus("Up from star 1 did not return to a Where to Watch provider")
            return
        }
        remote.press(.down)
        guard waitForFocus(firstStar, timeout: 2) else {
            failFocus("Down from the provider row did not return to star 1")
            return
        }
        remote.press(.down)
        guard waitForFocus(clear, timeout: 2) else {
            failFocus("Down from star 1 \(firstStar.frame) did not focus Clear rating \(clear.frame)")
            return
        }
        remote.press(.select)
        XCTAssertEqual(waitForStars("Not rated"), "Not rated")
        XCTAssertFalse(app.buttons["tv.movie.clearRating"].exists)
        XCTAssertEqual(app.descendants(matching: .any)["tv.movie.watchlist"].value as? String, "On")
        attach("tv-clear-\(halfStars)")

        app.terminate()
        app.launchArguments = ["-MRTOpenMovie", movie]
        app.launch()
        XCTAssertEqual(waitForStars("Not rated"), "Not rated")
        XCTAssertFalse(app.buttons["tv.movie.clearRating"].exists)
        XCTAssertEqual(app.descendants(matching: .any)["tv.movie.watchlist"].value as? String, "On")

        let oneStar = app.buttons["tv.movie.star.1"]
        XCTAssertTrue(oneStar.waitForExistence(timeout: 10))
        guard waitForFocusedProvider() != nil else {
            failFocus("Relaunch did not focus a provider")
            return
        }
        remote.press(.down)
        guard waitForFocus(oneStar, timeout: 2) else {
            failFocus("Down after relaunch did not focus star 1 \(oneStar.frame)")
            return
        }
        remote.press(.select)
        XCTAssertEqual(waitForStars("1 of 5 stars"), "1 of 5 stars")
        XCTAssertTrue(app.buttons["tv.movie.clearRating"].waitForExistence(timeout: 5))
        app.terminate()
    }

    private func waitForStars(_ expected: String) -> String {
        let stars = app.descendants(matching: .any)["tv.movie.stars"]
        let matched = NSPredicate(format: "value == %@", expected)
        _ = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: matched, object: stars)], timeout: 5)
        return stars.value as? String ?? ""
    }

    private func waitForFocusedProvider(timeout: TimeInterval = 8) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let provider = focusedProvider() { return provider }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return focusedProvider()
    }

    private func focusedProvider() -> XCUIElement? {
        let providers = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "tv.provider."))
        for index in 0..<providers.count {
            let button = providers.element(boundBy: index)
            if button.exists, button.hasFocus { return button }
        }
        return nil
    }

    private func failFocus(_ message: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "tv-focus-fail"
        shot.lifetime = .keepAlways
        add(shot)
        let body = message + "\n" + focusDump() + "\n\n" + app.debugDescription
        let text = XCTAttachment(data: Data(body.utf8), uniformTypeIdentifier: "public.plain-text")
        text.name = "tv-focus-ax"
        text.lifetime = .keepAlways
        add(text)
        XCTFail(message + "\n" + focusDump())
    }

    private func focusDump() -> String {
        var lines: [String] = []
        let providers = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "tv.provider."))
        for index in 0..<providers.count {
            let button = providers.element(boundBy: index)
            if button.exists {
                lines.append("\(button.identifier) \(button.label) focus=\(button.hasFocus) frame=\(button.frame)")
            }
        }
        for id in ["tv.movie.star.1", "tv.movie.clearRating", "tv.movie.yourRating", "tv.movie.listenerAverage"] {
            let element = app.descendants(matching: .any)[id]
            lines.append("\(id) exists=\(element.exists) focus=\(element.hasFocus) frame=\(element.exists ? String(describing: element.frame) : "nil")")
        }
        return lines.joined(separator: "\n")
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
