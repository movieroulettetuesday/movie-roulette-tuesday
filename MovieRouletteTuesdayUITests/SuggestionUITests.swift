import XCTest

/// Focused coverage of the Roulette-tab "Pick for Me" button, its fallbacks, and House Rules.
/// The on-device model is stubbed through DEBUG launch arguments, so this
/// does not need Apple Intelligence.
final class SuggestionUITests: XCTestCase {
    private var app: XCUIApplication!
    private var shotDir: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        let raw = ProcessInfo.processInfo.environment["MRT_SHOT_DIR"]
            ?? "/Users/mjstudley/Developer/MRT-BuildCheck/rc-102/nov11-step2/manual"
        shotDir = URL(fileURLWithPath: raw)
        try FileManager.default.createDirectory(at: shotDir, withIntermediateDirectories: true)
    }

    func testButtonShowsASuggestionCardWhenTheModelIsAvailable() throws {
        launch(gate: "available", style: "Light")
        let button = app.buttons["what-should-i-watch-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "the button should be on the Roulette tab when the model is available")
        XCTAssertEqual(button.label, "Pick for Me")
        let subtitle = app.staticTexts["pick-for-me-subtitle"]
        XCTAssertTrue(subtitle.exists)
        XCTAssertEqual(subtitle.label, "Not random: one movie chosen for you, and why it fits.")
        let hint = app.descendants(matching: .any)["roulette-status"].firstMatch
        XCTAssertTrue(
            hint.label == "Tap to spin: the wheel picks at random." || hint.label.hasPrefix("Last landed on"),
            "wheel hint was: \(hint.label)"
        )
        button.tap()

        let card = app.descendants(matching: .any)["suggestion-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["PICKED FOR YOU"].exists, "the title alone names the card")
        XCTAssertTrue(app.navigationBars["Picked for You"].exists)
        let title = app.descendants(matching: .any)["suggestion-title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "The Devil's Rain")
        let why = app.descendants(matching: .any)["suggestion-why"].firstMatch
        XCTAssertTrue(why.waitForExistence(timeout: 3))
        XCTAssertEqual(why.label, "Good for a scare.")
        // Facts come from the app's own lists (fresh ratings: nothing on the
        // watchlist, nothing rated), never from the model.
        let facts = app.descendants(matching: .any)["suggestion-facts"].firstMatch
        XCTAssertTrue(facts.exists)
        XCTAssertTrue(facts.label.contains("Not watched yet"), facts.label)
        XCTAssertFalse(facts.label.contains("On your watchlist"), facts.label)
        XCTAssertFalse(facts.label.contains("You rated it"), facts.label)
        XCTAssertTrue(app.buttons["suggestion-open-movie"].exists)
        XCTAssertTrue(app.buttons["suggestion-where-to-watch"].exists)
        XCTAssertTrue(app.buttons["suggestion-spin-instead"].exists)
        saveShot("suggestion-card-light")

        // Dark, same stub.
        launch(gate: "available", style: "Dark")
        XCTAssertTrue(app.buttons["what-should-i-watch-button"].waitForExistence(timeout: 10))
        app.buttons["what-should-i-watch-button"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["suggestion-card"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.descendants(matching: .any)["suggestion-title"].firstMatch.label, "The Devil's Rain")
        saveShot("suggestion-card-dark")
    }

    /// Matthew's pick (d): no answer in 2.5 s shows the app's own pick with
    /// the factual reason, not the Spin fallback.
    func testTimeoutShowsTheAppsOwnPickNotSpin() throws {
        launch(gate: "available", style: "Light", force: "timeout")
        let button = app.buttons["what-should-i-watch-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
        XCTAssertTrue(app.staticTexts["Picking from your watchlist and services…"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["suggestion-loading-spin-instead"].exists)
        XCTAssertTrue(app.buttons["suggestion-loading-cancel"].exists)
        let card = app.descendants(matching: .any)["suggestion-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        XCTAssertEqual(app.descendants(matching: .any)["suggestion-title"].firstMatch.label, "The Devil's Rain")
        // No vibe line on a fresh sim (not on the watchlist or a service); if an
        // earlier test chose Shudder in My Services, the true fallback line.
        let lead = app.descendants(matching: .any)["suggestion-why"].firstMatch
        if lead.exists { XCTAssertEqual(lead.label, "Picked from your watchlist and services.") }
        let facts = app.descendants(matching: .any)["suggestion-facts"].firstMatch
        XCTAssertTrue(facts.exists)
        XCTAssertTrue(facts.label.contains("Not watched yet"), facts.label)
        XCTAssertFalse(app.descendants(matching: .any)["suggestion-fallback-message"].exists, "no Spin fallback on timeout")
        saveShot("pick-timeout-own-pick-light")
    }

    func testHouseRulesExplainPickForMeSearchListsWidgetSiriAndSpotlight() throws {
        launch(gate: "available", style: "Light", extra: ["-MRTShowRules"])
        let list = app.descendants(matching: .any)["house-rules-list"].firstMatch
        XCTAssertTrue(app.navigationBars["House Rules"].waitForExistence(timeout: 10))
        // Rows are checked as their section scrolls by: the helper only swipes up.
        for section in ["pick", "search", "lists", "siri", "widget", "good"] {
            let header = app.descendants(matching: .any)["house-rules-section-\(section)"].firstMatch
            XCTAssertTrue(scrollTo(header, in: list), "section \(section)")
            if section == "siri" {
                let spin = app.descendants(matching: .any)["house-rules-row-siri-SpinMovieRouletteIntent"].firstMatch
                XCTAssertTrue(scrollTo(spin, in: list), "spin row")
                XCTAssertFalse(spin.label.contains("What should we watch"), spin.label)
                let pick = app.descendants(matching: .any)["house-rules-row-siri-WhatShouldIWatchIntent"].firstMatch
                XCTAssertTrue(scrollTo(pick, in: list), "pick row")
                XCTAssertTrue(pick.label.contains("“Pick a movie for me in Movie Roulette”"), pick.label)
                XCTAssertTrue(pick.label.contains("“What should I watch in Movie Roulette”"), pick.label)
            }
            if section == "widget" {
                let add = app.descendants(matching: .any)["house-rules-row-widget-add"].firstMatch
                XCTAssertTrue(scrollTo(add, in: list), "widget add row")
                XCTAssertTrue(add.label.contains("touch and hold the Home Screen, tap Edit, then Add Widget, and search Movie Roulette"), add.label)
            }
        }
        saveShot("house-rules-light")
    }

    private func scrollTo(_ element: XCUIElement, in list: XCUIElement) -> Bool {
        if element.waitForExistence(timeout: 2), element.isHittable { return true }
        for _ in 0..<14 {
            if element.exists, element.isHittable { return true }
            list.swipeUp()
        }
        return element.exists
    }

    func testButtonIsHiddenWhenTheModelIsUnavailable() throws {
        launch(gate: "unavailable", style: "Light")
        let wheel = app.descendants(matching: .any)["Roulette wheel"]
        XCTAssertTrue(wheel.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["what-should-i-watch-button"].exists, "the Roulette tab should look like it does today")
        saveShot("suggestion-hidden-light")

        launch(gate: "unavailable", style: "Dark")
        XCTAssertTrue(app.descendants(matching: .any)["Roulette wheel"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["what-should-i-watch-button"].exists)
        saveShot("suggestion-hidden-dark")
    }

    func testButtonStaysVisibleAndExplainsWhenTheModelIsNotReady() {
        launch(gate: "notReady", style: "Light")
        assertFallback(shot: "suggestion-not-ready-light")
        launch(gate: "notReady", style: "Dark")
        assertFallback(shot: "suggestion-not-ready-dark")
    }

    private func assertFallback(shot name: String) {
        let button = app.buttons["what-should-i-watch-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "the button stays on the Roulette tab when the model is not ready")
        button.tap()
        let message = app.descendants(matching: .any)["suggestion-fallback-message"].firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 8), "fallback message should appear after tapping the button")
        XCTAssertTrue(
            message.label.contains("aren’t ready") || message.label.contains("aren't ready"),
            "fallback text was: \(message.label)"
        )
        XCTAssertTrue(app.buttons["suggestion-spin-the-wheel"].waitForExistence(timeout: 3))
        saveShot(name)
    }

    private func launch(gate: String, style: String, force: String? = nil, extra: [String] = []) {
        app = XCUIApplication()
        // -AppleInterfaceStyle is not enough on the iOS 27 simulator; the device
        // appearance is what actually switches Light/Dark for screenshots.
        XCUIDevice.shared.appearance = (style == "Dark") ? .dark : .light
        app.launchArguments = [
            "-MRTNoSplash",
            "-MRTMockCommunity",
            "-MRTUITest",
            "-MRTStartTab", "roulette",
            "-MRTSuggestionGate", gate,
            "-AppleInterfaceStyle", style,
            // The app's Settings → Appearance (default System) is what
            // actually paints sheets; pin it so Light/Dark shots differ.
            "-settings.appearance", style.lowercased(),
        ] + extra
        // The stub stands in for the model: it answers pick 1 (this movie) and
        // a vibe. The facts on the card are still written by the app.
        app.launchEnvironment["MRT_SUGGESTION_MOVIE"] = "the-devils-rain-1975"
        app.launchEnvironment["MRT_SUGGESTION_VIBE"] = "scares"
        if let force { app.launchEnvironment["MRT_SUGGESTION_FORCE"] = force }
        app.launch()
    }

    private func saveShot(_ name: String) {
        let data = app.screenshot().pngRepresentation
        let url = shotDir.appendingPathComponent("\(name).png")
        do {
            try data.write(to: url)
        } catch {
            XCTFail("could not write \(url.path): \(error)")
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
