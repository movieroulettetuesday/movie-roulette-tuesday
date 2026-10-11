import XCTest
@testable import MovieRouletteTuesday

/// The storyboard badge and the SwiftUI cover's first frame must agree exactly,
/// and the curves must start at the launch frame and end at the real screen.
final class LaunchSplashTests: XCTestCase {
    func testBadgeGeometryMatchesTheStoryboard() throws {
        // iPhone 18 Pro (402 wide), SE (375), iPad portrait (1032) / landscape (1376).
        XCTAssertEqual(LaunchSplash.badgeDiameter(windowWidth: 402), 120.6, accuracy: 0.001)
        XCTAssertEqual(LaunchSplash.badgeDiameter(windowWidth: 375), 112.5, accuracy: 0.001)
        XCTAssertEqual(LaunchSplash.badgeDiameter(windowWidth: 1_032), 280)
        XCTAssertEqual(LaunchSplash.badgeDiameter(windowWidth: 1_376), 280)
        let c = LaunchSplash.badgeCenter(windowWidth: 402, windowHeight: 874)
        XCTAssertEqual(c.x, 201); XCTAssertEqual(c.y, 437 * LaunchSplash.badgeCenterYFactor, accuracy: 1e-9)
        XCTAssertEqual(c.y, 476.3, accuracy: 0.1)   // measured hub: 477
        // Storyboard constraints: image width = W * multiplier, capped; disc = 76% of the image.
        XCTAssertEqual(402 * LaunchSplash.storyboardWidthMultiplier * LaunchSplash.badgeImageDiscFraction, 120.6, accuracy: 0.001)
        XCTAssertEqual(LaunchSplash.storyboardMaxImageWidth * LaunchSplash.badgeImageDiscFraction, 280, accuracy: 0.001)
        XCTAssertEqual(LaunchSplash.badgeDiameter(windowWidth: .nan), 0)
    }

    func testStoryboardConstraintsUseTheSameConstants() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MovieRouletteTuesday/LaunchScreen.storyboard")
        guard let xml = try? String(contentsOf: url, encoding: .utf8) else {
            throw XCTSkip("storyboard source not reachable from this test host")
        }
        XCTAssertTrue(xml.contains("launchScreen=\"YES\""))
        XCTAssertTrue(xml.contains("image=\"LaunchGradient\""))
        XCTAssertTrue(xml.contains("image=\"LaunchBadge\""))
        XCTAssertTrue(xml.contains(String(format: "multiplier=\"%.6f\"", LaunchSplash.storyboardWidthMultiplier)))
        XCTAssertTrue(xml.contains(String(format: "constant=\"%.2f\"", LaunchSplash.storyboardMaxImageWidth)))
        XCTAssertTrue(xml.contains(String(format: "secondAttribute=\"centerY\" multiplier=\"%g\"", LaunchSplash.badgeCenterYFactor)))
    }

    func testCurvesStartAtTheLaunchFrameAndEndAtTheScreen() {
        let start = (x: 201.0, y: 449.0), hub = (x: 201.0, y: 455.0)
        for reduce in [false, true] {
            XCTAssertEqual(LaunchSplash.coverOpacity(progress: 0), 1)
            XCTAssertEqual(LaunchSplash.coverOpacity(progress: 1), 0)
            XCTAssertEqual(LaunchSplash.wheelOpacity(progress: 0), 0)
            XCTAssertEqual(LaunchSplash.wheelOpacity(progress: 1), 1)
            XCTAssertEqual(LaunchSplash.wheelScale(progress: 1, reduceMotion: reduce), 1)
            XCTAssertEqual(LaunchSplash.wheelRotationDegrees(progress: 1, reduceMotion: reduce), 0)
            XCTAssertEqual(LaunchSplash.badgeDiameter(progress: 0, start: 120.6, hub: 88, reduceMotion: reduce), 120.6)
            let c0 = LaunchSplash.badgeCenter(progress: 0, start: start, hub: hub, reduceMotion: reduce)
            XCTAssertEqual(c0.x, start.x); XCTAssertEqual(c0.y, start.y)
        }
        // Full motion: 24-degree settle, 0.82 scale-in, badge lands exactly on the hub.
        XCTAssertEqual(LaunchSplash.wheelRotationDegrees(progress: 0, reduceMotion: false), -24)
        XCTAssertEqual(LaunchSplash.wheelScale(progress: 0, reduceMotion: false), 0.82, accuracy: 1e-9)
        XCTAssertEqual(LaunchSplash.badgeDiameter(progress: 1, start: 120.6, hub: 88, reduceMotion: false), 88)
        let c1 = LaunchSplash.badgeCenter(progress: 1, start: start, hub: hub, reduceMotion: false)
        XCTAssertEqual(c1.y, hub.y)
        XCTAssertEqual(LaunchSplash.badgeOpacity(progress: 1, reduceMotion: false), 1)
        // Reduce Motion: nothing moves or scales; it is a crossfade.
        XCTAssertEqual(LaunchSplash.wheelRotationDegrees(progress: 0, reduceMotion: true), 0)
        XCTAssertEqual(LaunchSplash.wheelScale(progress: 0, reduceMotion: true), 1)
        XCTAssertEqual(LaunchSplash.badgeDiameter(progress: 0.5, start: 120.6, hub: 88, reduceMotion: true), 120.6)
        XCTAssertEqual(LaunchSplash.badgeOpacity(progress: 1, reduceMotion: true), 0)
        // Out-of-range / NaN progress is treated as finished.
        XCTAssertEqual(LaunchSplash.coverOpacity(progress: .nan), 0)
        XCTAssertEqual(LaunchSplash.coverOpacity(progress: 7), 0)
    }
}
