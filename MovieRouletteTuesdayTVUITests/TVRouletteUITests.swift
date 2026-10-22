import XCTest

/// Apple TV Roulette, driven with the Siri Remote: default focus, Select and
/// Play/Pause spins, the in-tab result, Menu back to the wheel, and the remote
/// during a spin (Play/Pause stops, swipes do nothing, Menu cancels).
/// Any "-MRT…" launch argument keeps the app on the bundled movie list (offline, deterministic).
final class TVRouletteUITests: XCTestCase {
    /// A spin lasts ~7 s (the recorded clip); a rare forced re-spin adds one more.
    private let spinTimeout: TimeInterval = 40
    private var app: XCUIApplication!
    private var remote: XCUIRemote { XCUIRemote.shared }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-MRTUITest"]
        app.launch()
    }

    private var spin: XCUIElement { app.buttons["tv.spin"] }
    private var spinAgain: XCUIElement { app.buttons["tv.spinAgain"] }

    private func waitForFocus(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let focused = NSPredicate(format: "exists == true AND hasFocus == true")
        return XCTWaiter().wait(for: [expectation(for: focused, evaluatedWith: element)], timeout: timeout) == .completed
    }

    private func waitForSpinning(timeout: TimeInterval = 5) -> Bool {
        let spinning = NSPredicate(format: "label == %@", "Spinning…")
        return XCTWaiter().wait(for: [expectation(for: spinning, evaluatedWith: spin)], timeout: timeout) == .completed
    }

    private func attachScreenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func test1LaunchFocusesSpin() {
        XCTAssertTrue(spin.waitForExistence(timeout: 20), "Spin pill on the Roulette tab")
        XCTAssertTrue(waitForFocus(spin), "Spin has default focus")
        XCTAssertTrue(app.otherElements["tv.wheel"].exists || app.descendants(matching: .any)["tv.wheel"].exists)
        attachScreenshot("tv-roulette-home")
    }

    func test2SelectSpinsThenResultThenMenuBack() {
        XCTAssertTrue(waitForFocus(spin, timeout: 20))
        remote.press(.select)
        XCTAssertTrue(spinAgain.waitForExistence(timeout: spinTimeout), "result appears in the tab after the spin")
        XCTAssertTrue(waitForFocus(spinAgain), "Spin Again is focused on the result")
        XCTAssertTrue(app.staticTexts["tv.result.title"].exists, "result shows the movie title")
        attachScreenshot("tv-roulette-result")

        remote.press(.menu)
        XCTAssertTrue(waitForFocus(spin), "Menu returns to the wheel with Spin focused")
        XCTAssertFalse(spinAgain.exists)
        XCTAssertTrue(app.descendants(matching: .any)["tv.lastLanded"].exists, "Last landed on shows the spin")
        XCTAssertEqual(app.state, .runningForeground, "Menu on the result does not leave the app")
    }

    func test3PlayPauseSpinsAndSpinsAgain() {
        XCTAssertTrue(waitForFocus(spin, timeout: 20))
        remote.press(.playPause)
        XCTAssertTrue(spinAgain.waitForExistence(timeout: spinTimeout), "Play/Pause spins from the home layout")
        let first = app.staticTexts["tv.result.title"].label

        remote.press(.playPause)  // = Spin Again
        let gone = NSPredicate(format: "exists == false")
        XCTAssertEqual(XCTWaiter().wait(for: [expectation(for: gone, evaluatedWith: spinAgain)], timeout: 5), .completed,
                       "Play/Pause on the result starts a new spin")
        XCTAssertTrue(spinAgain.waitForExistence(timeout: spinTimeout), "second result")
        XCTAssertTrue(waitForFocus(spinAgain))
        _ = first  // titles may repeat (random); the reappearing result is the check
    }

    func test4PlayPauseStopsSpinEarly() {
        XCTAssertTrue(waitForFocus(spin, timeout: 20))
        remote.press(.select)
        XCTAssertTrue(waitForSpinning(), "Select starts a spin")
        let pressed = Date()
        remote.press(.playPause)  // = Stop while spinning
        XCTAssertTrue(spinAgain.waitForExistence(timeout: spinTimeout), "a stopped spin still shows its result")
        // A full spin is ~7 s; a stopped one settles in ~1 s. (A rare forced
        // re-spin after the stop adds ~9 s: rerun once if this trips.)
        XCTAssertLessThan(Date().timeIntervalSince(pressed), 5, "Play/Pause stopped the spin early")
        XCTAssertTrue(waitForFocus(spinAgain))
    }

    func test5SwipesDoNothingAndMenuCancelsSpin() {
        XCTAssertTrue(waitForFocus(spin, timeout: 20))
        remote.press(.select)
        XCTAssertTrue(waitForSpinning(), "Select starts a spin")
        remote.press(.up)
        remote.press(.right)
        remote.press(.left)
        XCTAssertTrue(waitForFocus(spin, timeout: 2), "swipes during a spin leave focus on Spin")
        XCTAssertEqual(spin.label, "Spinning…", "still spinning on the Roulette tab")

        remote.press(.menu)  // = cancel the spin
        let idle = NSPredicate(format: "label == %@", "Spin")
        XCTAssertEqual(XCTWaiter().wait(for: [expectation(for: idle, evaluatedWith: spin)], timeout: 5), .completed,
                       "Menu cancels the spin")
        XCTAssertTrue(waitForFocus(spin), "back on the wheel home with Spin focused")
        XCTAssertFalse(spinAgain.waitForExistence(timeout: 10), "a cancelled spin shows no result")
        XCTAssertFalse(app.descendants(matching: .any)["tv.lastLanded"].exists, "a cancelled spin is not recorded")
        XCTAssertEqual(app.state, .runningForeground, "Menu during a spin does not leave the app")
    }
}
