import XCTest
import MRTCore

/// Cancel and a failed open are the same `false` completion. tvOS lists the
/// https search first and the custom scheme second (`TVProviderLaunching`).
/// iOS lists the scheme first. Either order, a refusal must not open the rest:
/// that next URL still launches the provider.
final class ProviderOpenPolicyTests: XCTestCase {
    func testCancelDoesNotOpenAFollowUpURL() {
        let pages: [[URL]] = [
            [
                URL(string: "https://www.netflix.com/search?q=The%20Matrix")!,
                URL(string: "nflx://www.netflix.com/search?q=The%20Matrix")!,
            ],
            [
                URL(string: "https://www.disneyplus.com/search?q=The%20Matrix")!,
                URL(string: "disneyplus://")!,
            ],
            [
                URL(string: "https://tv.apple.com/us/search?term=The%20Matrix")!,
                URL(string: "videos://")!,
            ],
            [
                URL(string: "aiv://aiv/search?query=The%20Matrix")!,
                URL(string: "https://app.primevideo.com/search?phrase=The%20Matrix")!,
                URL(string: "https://www.amazon.com/s?i=instant-video&k=The%20Matrix")!,
            ],
        ]
        for urls in pages {
            expectSingleOpen(urls, declined: urls[0])
        }
    }

    func testConfirmedOpenDoesNotOpenAFollowUpURL() {
        let web = URL(string: "https://www.netflix.com/search?q=The%20Matrix")!
        let app = URL(string: "nflx://www.netflix.com/search?q=The%20Matrix")!
        var opened: [URL] = []
        var result: ProviderOpenPolicy.Result?
        ProviderOpenPolicy.openFirst(of: [web, app], using: { url, completion in
            opened.append(url)
            completion(true)
        }, completion: { result = $0 })
        XCTAssertEqual(opened, [web])
        XCTAssertEqual(result, .opened(web))
    }

    func testOpenFirstWithNothingToOpenDoesNotCallTheOpener() {
        var opened = 0
        var result: ProviderOpenPolicy.Result?
        ProviderOpenPolicy.openFirst(of: [], using: { _, _ in
            opened += 1
        }, completion: { result = $0 })
        XCTAssertEqual(opened, 0)
        XCTAssertEqual(result, ProviderOpenPolicy.Result.none)
        XCTAssertNil(ProviderOpenPolicy.urlToOpen([]))
    }

    private func expectSingleOpen(_ urls: [URL], declined: URL) {
        var opened: [URL] = []
        var result: ProviderOpenPolicy.Result?
        ProviderOpenPolicy.openFirst(of: urls, using: { url, completion in
            opened.append(url)
            completion(false)
        }, completion: { result = $0 })
        XCTAssertEqual(ProviderOpenPolicy.urlToOpen(urls), declined)
        XCTAssertEqual(opened, [declined])
        XCTAssertEqual(result, .declined(declined))
    }
}
