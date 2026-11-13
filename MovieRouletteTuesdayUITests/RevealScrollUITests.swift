import XCTest

/// Longest reveal title at a large Dynamic Type size: Share and Movie page stay hittable,
/// scrolling the sheet only if the content overflows.
final class RevealScrollUITests: XCTestCase {
    private let longestID = "the-unbearable-weight-of-massive-talent-2022"
    private let longestTitle = "The Unbearable Weight of Massive Talent"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testShareAndMoviePageAreHittableWithLongestTitleAtAccessibilityXXXL() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-MRTNoSplash",
            "-MRTMockCommunity",
            "-MRTUITest",
            "-MRTRevealMovie", longestID,
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()

        let title = app.staticTexts[longestTitle]
        XCTAssertTrue(title.waitForExistence(timeout: 12), "reveal sheet shows the longest title")

        // ViewThatFits may leave both the fitting and scrolling copies in the
        // accessibility tree. Any one Share and any one Movie page being
        // hittable is enough; swipe the overflow scroll until they are.
        XCTAssertTrue(waitUntilHittable(id: "reveal-share", label: "Share", in: app, timeout: 10),
                      "Share is hittable with the longest title at AXXXL")
        XCTAssertTrue(waitUntilHittable(id: "reveal-movie-page", label: "Movie page", in: app, timeout: 6),
                      "Movie page is hittable with the longest title at AXXXL")
    }

    /// True when any match for `id` or `label` is hittable, after swiping the
    /// sheet up if the action row starts off-screen.
    @discardableResult
    private func waitUntilHittable(id: String, label: String, in app: XCUIApplication,
                                   timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var swipes = 0
        while Date() < deadline {
            if isAnyHittable(id: id, label: label, in: app) { return true }
            if swipes < 6 {
                swipeSheetUp(app)
                swipes += 1
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        }
        return isAnyHittable(id: id, label: label, in: app)
    }

    private func isAnyHittable(id: String, label: String, in app: XCUIApplication) -> Bool {
        let queries: [XCUIElementQuery] = [
            app.descendants(matching: .any).matching(identifier: id),
            app.buttons.matching(identifier: id),
            app.buttons.matching(NSPredicate(format: "label == %@", label)),
        ]
        for query in queries {
            let n = query.count
            for i in 0..<n {
                let el = query.element(boundBy: i)
                if el.exists && el.isHittable { return true }
            }
        }
        return false
    }

    private func swipeSheetUp(_ app: XCUIApplication) {
        if app.scrollViews.firstMatch.exists {
            app.scrollViews.firstMatch.swipeUp()
        } else if app.sheets.firstMatch.exists {
            app.sheets.firstMatch.swipeUp()
        } else {
            app.swipeUp()
        }
    }
}
