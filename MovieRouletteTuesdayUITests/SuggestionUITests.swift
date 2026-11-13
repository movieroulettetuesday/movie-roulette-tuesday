import XCTest

/// Focused coverage of the Roulette-tab button and the unavailable fallback.
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
        XCTAssertEqual(button.label, "What should I watch?")
        button.tap()

        let card = app.descendants(matching: .any)["suggestion-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        let title = app.descendants(matching: .any)["suggestion-title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "The Devil's Rain")
        let why = app.descendants(matching: .any)["suggestion-why"].firstMatch
        XCTAssertTrue(why.waitForExistence(timeout: 3))
        XCTAssertTrue(why.label.contains("watchlist"))
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

    private func launch(gate: String, style: String) {
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
        ]
        // Environment, not launch arguments: XCTest splits apostrophes in
        // "-MRTSuggestionWhy It's on your watchlist…".
        app.launchEnvironment["MRT_SUGGESTION_MOVIE"] = "the-devils-rain-1975"
        app.launchEnvironment["MRT_SUGGESTION_WHY"] =
            "It's on your watchlist, it's Horror, and it's on Shudder — one of your services."
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
