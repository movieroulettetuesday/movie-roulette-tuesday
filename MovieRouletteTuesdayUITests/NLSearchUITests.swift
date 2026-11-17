import XCTest

/// 1.1 natural-language search on iPhone and iPad with a STUBBED parser
/// (`MRT_NL_STUBS`) and a forced availability gate (`-MRTNLSearchGate`), so no
/// Apple Intelligence is needed. Checks chips, chip removal, the list switch
/// in both directions (source cleared, no bounce, iPad detail reset), and
/// that an unavailable model leaves keyword search alone. apply() and the
/// switch rule are unit-tested exactly in NLSearch*Tests.
final class NLSearchUITests: XCTestCase {
    private var app: XCUIApplication!
    private let moviesPrompt = "Title, year, S4E39, service"
    private let episodesPrompt = "Title, S4E39, or movie"

    private static let stubs: [String: [String: Any]] = [
        "free 80s horror I haven't watched": ["genre": "Horror", "yearMin": 1980, "yearMax": 1989, "freeOnly": true, "watched": "unwatched"],
        "episodes about The Thing": ["kind": "episode", "title": "The Thing"],
        "show me movies I haven't watched": ["kind": "movie", "watched": "unwatched"],
        "free horror": ["genre": "Horror", "freeOnly": true],
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
    }

    private func launch(tab: String, gate: String = "available") throws {
        app = XCUIApplication()
        app.launchArguments = ["-MRTNoSplash", "-MRTMockCommunity", "-MRTUITest", "-MRTStartTab", tab, "-MRTNLSearchGate", gate]
        let json = try JSONSerialization.data(withJSONObject: Self.stubs, options: [.sortedKeys])
        app.launchEnvironment["MRT_NL_STUBS"] = String(decoding: json, as: UTF8.self)
        app.launch()
    }

    private func searchField() -> XCUIElement {
        let field = app.searchFields.firstMatch
        if !field.waitForExistence(timeout: 8) || !field.isHittable { app.swipeDown() }
        XCTAssertTrue(field.waitForExistence(timeout: 10), "search field")
        return field
    }

    /// Replaces the field's text. Uses the field's clear button when there is
    /// text, since a tap can land the cursor mid-way through a long question.
    private func type(_ text: String, into field: XCUIElement) {
        field.tap()
        let clear = field.buttons["Clear text"]
        if clear.exists {
            clear.tap()
            // On iPad the clear button can drop keyboard focus.
            field.tap()
        } else {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 40))
        }
        field.typeText(text)
    }

    /// After a switch the destination's search is active (as while typing),
    /// so on iPhone the keyboard covers the tab bar. Tap the keyboard's Search
    /// key, as a person would, to leave the query and chips in place.
    private func dismissKeyboard() {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else { return }
        let search = keyboard.buttons.matching(NSPredicate(format: "label ==[c] 'search'")).firstMatch
        if search.exists { search.tap() }
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5), "keyboard dismissed")
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    private func tapTab(_ name: String) {
        let bar = app.tabBars.buttons[name]
        if bar.exists { bar.tap() } else { app.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch.tap() }
    }

    /// The visible list, told apart by its search prompt. Never pulls the
    /// list down: after a switch the destination's field must already show
    /// the moved query.
    private func waitForList(prompt: String, value: String? = nil, timeout: TimeInterval = 10) -> Bool {
        let predicate = NSPredicate { [weak self] _, _ in
            guard let field = self?.app.searchFields.firstMatch, field.exists else { return false }
            guard field.placeholderValue == prompt else { return false }
            if let value { return (field.value as? String) == value }
            return true
        }
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: timeout) == .completed
    }

    /// Right after a switch, with no pull-down: the destination's search
    /// field is on screen (not collapsed under the large title) and shows
    /// the moved query.
    private func assertMovedQueryVisible(_ prompt: String, _ query: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitForList(prompt: prompt, value: query), "destination field has the moved query", file: file, line: line)
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.exists && field.isHittable && !field.frame.isEmpty,
                      "moved query visible without pulling down", file: file, line: line)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(field.frame), "field on screen", file: file, line: line)
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testQuestionShowsChipsAndRemovingAChipChangesResults() throws {
        try launch(tab: "movies")
        let field = searchField()
        type("free 80s horror I haven't watched", into: field)
        for chip in ["nl-chip-genre", "nl-chip-years", "nl-chip-free", "nl-chip-watched"] {
            XCTAssertTrue(element(chip).waitForExistence(timeout: 8), chip)
        }
        XCTAssertFalse(element("nl-chip-title").exists, "filters-only question has no title chip")
        // Title order: the first free 80s horror; nothing outside the decade.
        XCTAssertTrue(element("movie-row-christmas-evil-1980").waitForExistence(timeout: 8), "free 80s horror")
        XCTAssertFalse(element("movie-row-antichrist-2009").exists, "2009 is outside 1980–1989")
        attach("nl-movies-chips")

        element("nl-chip-years").tap()
        XCTAssertTrue(element("nl-chip-years").waitForNonExistence(timeout: 5), "chip removed")
        XCTAssertTrue(element("nl-chip-genre").exists)
        XCTAssertTrue(element("movie-row-antichrist-2009").waitForExistence(timeout: 8), "results widen without the years chip")
        attach("nl-movies-chip-removed")
    }

    func testTitleLikeQueryStaysKeywordWithNoChips() throws {
        try launch(tab: "movies")
        type("the thing", into: searchField())
        XCTAssertTrue(element("movie-row-the-thing-1982").waitForExistence(timeout: 8))
        // Past the debounce: still no chips.
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertFalse(element("nl-chip-title").exists)
    }

    func testEpisodeQuestionOnMoviesSwitchesToEpisodesAndClearsMovies() throws {
        try launch(tab: "movies")
        type("episodes about The Thing", into: searchField())
        assertMovedQueryVisible(episodesPrompt, "episodes about The Thing")
        XCTAssertTrue(element("nl-chip-title").waitForExistence(timeout: 8), "chips moved")
        XCTAssertTrue(element("episode-row").firstMatch.waitForExistence(timeout: 45), "episode results")
        attach("nl-switch-to-episodes")

        dismissKeyboard()
        tapTab("Movies")
        // The handoff dismissed this list's search, so on iPhone the field
        // is collapsed under the title until the list is pulled down.
        _ = searchField()
        XCTAssertTrue(waitForList(prompt: moviesPrompt), "back on Movies")
        let movies = app.searchFields.firstMatch
        XCTAssertTrue((movies.value as? String) == moviesPrompt || (movies.value as? String) == "", "Movies query cleared")
        XCTAssertFalse(element("nl-chip-title").exists, "Movies chips cleared")
        XCTAssertFalse(app.keyboards.firstMatch.exists, "Movies search was dismissed by the handoff")
        Thread.sleep(forTimeInterval: 1.0)
        let field = app.searchFields.firstMatch
        XCTAssertFalse(field.exists && field.placeholderValue == episodesPrompt, "no bounce back to Episodes")
        XCTAssertFalse(element("nl-chip-title").exists, "no bounce: chips did not come back")
    }

    func testMovieQuestionOnEpisodesSwitchesToMovies() throws {
        try launch(tab: "episodes")
        type("show me movies I haven't watched", into: searchField())
        assertMovedQueryVisible(moviesPrompt, "show me movies I haven't watched")
        XCTAssertTrue(element("nl-chip-watched").waitForExistence(timeout: 8))
        // Ratings were reset (-MRTUITest), so every movie is unwatched; first by title.
        XCTAssertTrue(element("movie-row-a-face-in-the-crowd-1957").waitForExistence(timeout: 8), "unwatched movies listed")
        attach("nl-switch-to-movies")
        dismissKeyboard()
        tapTab("Episodes")
        // The handoff dismissed this list's search, so on iPhone the field
        // is collapsed under the title until the list is pulled down.
        _ = searchField()
        XCTAssertTrue(waitForList(prompt: episodesPrompt), "back on Episodes")
        XCTAssertFalse(element("nl-chip-watched").exists, "Episodes chips cleared")
    }

    /// iPad: the destination sidebar has the query and chips and the detail
    /// column resets. iPhone: the destination pops to its list.
    func testSwitchResetsDestinationDetail() throws {
        try launch(tab: "episodes")
        let row = element("episode-row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 45), "episodes loaded")
        row.tap()
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        if isPad {
            XCTAssertTrue(app.staticTexts["Pick an Episode"].waitForNonExistence(timeout: 8), "an episode is open")
        }
        tapTab("Movies")
        type("episodes about The Thing", into: searchField())
        assertMovedQueryVisible(episodesPrompt, "episodes about The Thing")
        XCTAssertTrue(element("nl-chip-title").waitForExistence(timeout: 8), "chips in the sidebar")
        if isPad {
            XCTAssertTrue(app.staticTexts["Pick an Episode"].waitForExistence(timeout: 8), "detail column reset")
        } else {
            XCTAssertFalse(app.navigationBars.buttons["Episodes"].exists, "popped to the list")
        }
        attach("nl-switch-detail-reset")
    }

    func testUnavailableModelKeepsKeywordSearchAndNeverSwitches() throws {
        try launch(tab: "movies", gate: "unavailable")
        type("episodes about The Thing", into: searchField())
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(waitForList(prompt: moviesPrompt, value: "episodes about The Thing", timeout: 2), "stayed on Movies")
        XCTAssertFalse(element("nl-chip-title").exists, "no chips")
        type("devils rain", into: app.searchFields.firstMatch)
        XCTAssertTrue(element("movie-row-the-devils-rain-1975").waitForExistence(timeout: 8), "keyword search as before")
    }
}
