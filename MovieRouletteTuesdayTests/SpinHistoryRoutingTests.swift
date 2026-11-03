import XCTest
import UserNotifications
@testable import MovieRouletteTuesday

final class SpinHistoryRoutingTests: XCTestCase {
    private let catalog = MovieCatalog(
        schemaVersion: 2,
        show: .mrt,
        categories: [RouletteCategory(id: "c", name: "C", colorHex: "#123456")],
        movies: [
            Movie(id: "two-eps", title: "Two Episodes", year: 2001, genre: "Drama", categories: ["c"],
                  episodeIds: ["Buzzsprout-old", "Buzzsprout-new"]),
            Movie(id: "no-eps", title: "Not Discussed", year: 2002, genre: "Drama", categories: ["c"]),
        ]
    )

    private func spin(_ movieId: String) -> SpinResult {
        SpinResult(movieId: movieId, categoryId: "c")
    }

    private func episode(_ guid: String) -> PodcastEpisode {
        PodcastEpisode(guid: guid, title: guid)
    }

    func testOpensFirstEpisodeThatIsInTheFeed() {
        let feed = ["Buzzsprout-old": episode("Buzzsprout-old"), "Buzzsprout-new": episode("Buzzsprout-new")]
        XCTAssertEqual(SpinHistoryRouting.destination(for: spin("two-eps"), catalog: catalog, episodesByGUID: feed),
                       .episode("Buzzsprout-old"))
        // First id not in the feed (yet): falls through to the next one.
        let partial = ["Buzzsprout-new": episode("Buzzsprout-new")]
        XCTAssertEqual(SpinHistoryRouting.destination(for: spin("two-eps"), catalog: catalog, episodesByGUID: partial),
                       .episode("Buzzsprout-new"))
    }

    func testFallsBackToMoviePage() {
        // Feed not loaded / episode missing.
        XCTAssertEqual(SpinHistoryRouting.destination(for: spin("two-eps"), catalog: catalog, episodesByGUID: [:]),
                       .movie("two-eps"))
        // Movie never discussed: movie page.
        XCTAssertEqual(SpinHistoryRouting.destination(for: spin("no-eps"), catalog: catalog,
                                                      episodesByGUID: ["Buzzsprout-old": episode("Buzzsprout-old")]),
                       .movie("no-eps"))
    }

    func testUnknownMovieOrNoCatalogIsNotTappable() {
        XCTAssertNil(SpinHistoryRouting.destination(for: spin("gone-from-catalog"), catalog: catalog, episodesByGUID: [:]))
        XCTAssertNil(SpinHistoryRouting.destination(for: spin("two-eps"), catalog: nil,
                                                    episodesByGUID: ["Buzzsprout-old": episode("Buzzsprout-old")]))
    }
}

/// 1.0 (10) crashed when a new-episode banner was tapped: the notification
/// delegate's completion ran off the main thread. Tapping must route to the
/// episode and complete on main, whatever thread the delegate is called from.
final class NotificationTapRoutingTests: XCTestCase {
    @MainActor
    func testTapFromBackgroundThreadRoutesAndCompletesOnMain() {
        AppRouter.shared.pendingURL = nil
        let done = expectation(description: "completion")
        DispatchQueue.global(qos: .userInitiated).async {
            NotificationRouter.shared.handleTap(episodeGUID: "Buzzsprout-19913482") {
                XCTAssertTrue(Thread.isMainThread, "completion handler must run on main")
                MainActor.assumeIsolated {
                    XCTAssertEqual(AppRouter.shared.pendingURL, DeepLink.episode(guid: "Buzzsprout-19913482").url)
                }
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 5)
        AppRouter.shared.pendingURL = nil
    }

    @MainActor
    func testTapOnMainWithoutGUIDCompletesSynchronously() {
        AppRouter.shared.pendingURL = nil
        var completed = false
        NotificationRouter.shared.handleTap(episodeGUID: nil) {
            XCTAssertTrue(Thread.isMainThread)
            completed = true
        }
        XCTAssertTrue(completed)
        XCTAssertNil(AppRouter.shared.pendingURL)
    }
}

// MARK: - Notification-tap crash repro (1.0 (10) SIGABRT)

/// Reproduces the 1.0 (10) notification-tap crash path. The system calls the
/// delegate's Objective-C selector
/// `userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:`
/// and UIKit's completion handler asserts it runs on the main thread
/// (NSInternalInconsistencyException "Call must be made on main thread" in
/// `_updateSnapshotAndStateRestorationWithAction`). This calls that same selector
/// from a detached (background) Swift Concurrency task and checks that the
/// completion handler and the routing both run on main.
/// 1.0 implemented the `async` didReceive; its compiler @objc thunk calls the
/// completion handler off the main thread, so this test fails there.
final class NotificationTapCrashReproTests: XCTestCase {
    static let guid = "Buzzsprout-19913482"

    func testDidReceiveFromDetachedTaskCompletesAndRoutesOnMain() async {
        await MainActor.run { AppRouter.shared.pendingURL = nil }
        let probe = TapProbe()
        let done = expectation(description: "didReceive completion handler called")
        let guid = Self.guid
        Task.detached {
            probe["callerOnMain"] = TapReproSupport.isMainThread()
            guard let response = TapReproSupport.makeResponse(guid: guid) else {
                probe["responseBuilt"] = false
                done.fulfill()
                return
            }
            probe["responseBuilt"] = true
            TapReproSupport.callDidReceive(response) {
                let onMain = TapReproSupport.isMainThread()
                probe["completionOnMain"] = onMain
                if onMain {
                    probe["routedBeforeCompletion"] = MainActor.assumeIsolated {
                        AppRouter.shared.pendingURL == DeepLink.episode(guid: guid).url
                    }
                }
                done.fulfill()
            }
        }
        await fulfillment(of: [done], timeout: 10)
        print("MRT-REPRO didReceive \(probe.summary)")
        XCTAssertEqual(probe["responseBuilt"], true, "could not build a UNNotificationResponse")
        XCTAssertEqual(probe["callerOnMain"], false, "the delegate must be called from a background thread")
        XCTAssertEqual(probe["completionOnMain"], true,
                       "didReceive completion handler ran OFF the main thread (UIKit asserts on this: the 1.0 crash)")
        XCTAssertEqual(probe["routedBeforeCompletion"], true, "routing is done on main before the completion handler")
        await MainActor.run { AppRouter.shared.pendingURL = nil }
    }
}

/// Thread-safe flags shared between the detached task and the test.
final class TapProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Bool] = [:]
    subscript(key: String) -> Bool? {
        get { lock.lock(); defer { lock.unlock() }; return values[key] }
        set { lock.lock(); values[key] = newValue; lock.unlock() }
    }
    var summary: String {
        lock.lock(); defer { lock.unlock() }
        return values.keys.sorted().map { "\($0)=\(values[$0].map(String.init) ?? "nil")" }.joined(separator: " ")
    }
}

enum TapReproSupport {
    static func isMainThread() -> Bool { Thread.isMainThread }

    /// UNNotificationResponse has no public initializer: decode empty instances and
    /// fill in the request through KVC (test-only).
    static func makeResponse(guid: String) -> UNNotificationResponse? {
        let content = UNMutableNotificationContent()
        content.title = "New episode"
        content.userInfo = [NewEpisodeAlerts.guidUserInfoKey: guid]
        let request = UNNotificationRequest(identifier: "mrt-repro-\(guid)", content: content, trigger: nil)
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.finishEncoding()
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: archiver.encodedData) else { return nil }
        coder.requiresSecureCoding = false
        defer { coder.finishDecoding() }
        guard let notification = UNNotification(coder: coder),
              let response = UNNotificationResponse(coder: coder) else { return nil }
        notification.setValue(request, forKey: "request")
        response.setValue(notification, forKey: "notification")
        response.setValue(UNNotificationDefaultActionIdentifier, forKey: "actionIdentifier")
        return response
    }

    /// Calls the delegate through the Objective-C protocol selector, exactly as
    /// UserNotifications does when a banner is tapped.
    static func callDidReceive(_ response: UNNotificationResponse, completion: @escaping () -> Void) {
        let delegate: UNUserNotificationCenterDelegate = NotificationRouter.shared
        delegate.userNotificationCenter?(UNUserNotificationCenter.current(), didReceive: response,
                                         withCompletionHandler: completion)
    }
}

/// 1.0.1 API: `handleTap(episodeGUID:completion:)` called from a detached task.
final class NotificationHandleTapReproTests: XCTestCase {
    func testHandleTapFromDetachedTaskCompletesAndRoutesOnMain() async {
        await MainActor.run { AppRouter.shared.pendingURL = nil }
        let probe = TapProbe()
        let done = expectation(description: "handleTap completion called")
        let guid = NotificationTapCrashReproTests.guid
        Task.detached {
            probe["callerOnMain"] = TapReproSupport.isMainThread()
            NotificationRouter.shared.handleTap(episodeGUID: guid) {
                let onMain = TapReproSupport.isMainThread()
                probe["completionOnMain"] = onMain
                if onMain {
                    probe["routedBeforeCompletion"] = MainActor.assumeIsolated {
                        AppRouter.shared.pendingURL == DeepLink.episode(guid: guid).url
                    }
                }
                done.fulfill()
            }
        }
        await fulfillment(of: [done], timeout: 10)
        print("MRT-REPRO handleTap \(probe.summary)")
        XCTAssertEqual(probe["callerOnMain"], false, "handleTap must be called from a background thread")
        XCTAssertEqual(probe["completionOnMain"], true, "completion must run on main")
        XCTAssertEqual(probe["routedBeforeCompletion"], true, "routing is done on main before the completion handler")
        await MainActor.run { AppRouter.shared.pendingURL = nil }
    }
}
