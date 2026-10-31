import XCTest
@testable import MovieRouletteTuesday

/// Provider → scheme/host, in the spirit of ParamountProviderTests: the tap
/// picks an app search when we know one, otherwise a web search, otherwise TMDB.
final class ProviderLaunchingTests: XCTestCase {
    private typealias P = StreamingInfo.Provider

    private func movie(_ title: String = "The Matrix", tmdbId: Int? = 603, link: String? = nil) -> Movie {
        Movie(
            id: "the-matrix",
            title: title,
            year: 1999,
            genre: "Sci-Fi",
            tmdbId: tmdbId,
            streaming: link.map { StreamingInfo(link: $0) }
        )
    }

    func testKnownProvidersMapToSchemeAndHost() {
        let title = "The Matrix"
        let film = movie(title)
        // id, name, app scheme, first web host, web query name, app query name
        let rows: [(Int, String, String?, String, String?, String?)] = [
            (8, "Netflix", "nflx", "www.netflix.com", "q", "q"),
            (1796, "Netflix Standard with Ads", "nflx", "www.netflix.com", "q", "q"),
            (9, "Amazon Prime Video", "aiv", "app.primevideo.com", "phrase", "query"),
            (10, "Amazon Video", "aiv", "app.primevideo.com", "phrase", "query"),
            (2100, "Amazon Prime Video with Ads", "aiv", "app.primevideo.com", "phrase", "query"),
            (1899, "HBO Max", nil, "play.max.com", "q", nil),
            (384, "HBO", nil, "play.max.com", "q", nil),
            (2, "Apple TV Store", nil, "tv.apple.com", "term", nil),
            (350, "Apple TV", nil, "tv.apple.com", "term", nil),
            (337, "Disney Plus", nil, "www.disneyplus.com", "q", nil),
            (15, "Hulu", nil, "www.hulu.com", "q", nil),
            (531, "Paramount Plus", nil, "www.paramountplus.com", "q", nil),
            (2303, "Paramount Plus Premium", nil, "www.paramountplus.com", "q", nil),
            (386, "Peacock Premium", nil, "www.peacocktv.com", "q", nil),
            (387, "Peacock Premium Plus", nil, "www.peacocktv.com", "q", nil),
            (73, "Tubi TV", nil, "tubitv.com", nil, nil),
            (258, "Criterion Channel", nil, "www.criterionchannel.com", "q", nil),
            (192, "YouTube", "youtube", "www.youtube.com", "search_query", "search_query"),
            (235, "YouTube Free", "youtube", "www.youtube.com", "search_query", "search_query"),
            (11, "MUBI", nil, "mubi.com", "query", nil),
            (300, "Pluto TV", nil, "pluto.tv", "q", nil),
            (99, "Shudder", nil, "www.shudder.com", "q", nil),
            (361, "TCM", nil, "www.tcm.com", "q", nil),
        ]

        for (id, name, scheme, host, query, appQuery) in rows {
            let destination = ProviderLaunching.destination(for: P(id: id, name: name), movie: film)
            XCTAssertEqual(destination.appURL?.scheme, scheme, name)
            XCTAssertEqual(destination.webURL?.host, host, name)
            XCTAssertEqual(destination.webURL?.scheme, "https", name)
            if let query {
                XCTAssertEqual(queryValue(query, destination.webURL), title, name)
            }
            if let appQuery {
                XCTAssertEqual(queryValue(appQuery, destination.appURL), title, name)
            }
            XCTAssertFalse(destination.urls.contains { $0.host == "www.themoviedb.org" }, name)
        }
    }

    func testNameMatchIsCaseInsensitiveAndIdsWin() {
        let film = movie()
        XCTAssertEqual(
            ProviderLaunching.destination(for: P(id: 1, name: "NETFLIX"), movie: film).appURL?.scheme,
            "nflx"
        )
        XCTAssertEqual(
            ProviderLaunching.destination(for: P(id: 531, name: "P+"), movie: film).webURL?.host,
            "www.paramountplus.com"
        )
        XCTAssertEqual(
            ProviderLaunching.destination(for: P(id: 999, name: "Max"), movie: film).webURL?.host,
            "play.max.com"
        )
    }

    func testOtherBrandsStorefrontsDoNotStealAppleOrYouTube() {
        let film = movie()
        let others: [(Int, String)] = [
            (1854, "AMC Plus Apple TV channel"),
            (2061, "Cinemax Apple TV channel"),
            (2528, "YouTube TV"),
            (289, "Cinemax Amazon Channel"),
            (7, "Fandango At Home"),
            (538, "Plex"),
        ]
        for (id, name) in others {
            let destination = ProviderLaunching.destination(for: P(id: id, name: name), movie: film)
            XCTAssertNil(destination.appURL, name)
            XCTAssertEqual(destination.webURL?.host, "www.themoviedb.org", name)
            XCTAssertEqual(destination.hint, "Opens all options on TMDB", name)
        }
        XCTAssertEqual(
            ProviderLaunching.destination(for: P(id: 2243, name: "Apple TV Amazon Channel"), movie: film).webURL?.host,
            "tv.apple.com"
        )
    }

    func testInstalledAppIsTriedBeforeTheWebsite() {
        let film = movie("The Matrix")
        let netflix = ProviderLaunching.destination(for: P(id: 8, name: "Netflix"), movie: film)
        let installed = netflix.attempts { $0.scheme == "nflx" }
        XCTAssertEqual(installed.first?.scheme, "nflx")
        XCTAssertEqual(installed.last?.host, "www.netflix.com")

        let missing = netflix.attempts { _ in false }
        XCTAssertEqual(missing.map(\.scheme), ["https"])
        XCTAssertEqual(missing.first?.host, "www.netflix.com")

        let prime = ProviderLaunching.destination(for: P(id: 9, name: "Amazon Prime Video"), movie: film)
        let primeWeb = prime.attempts { _ in false }
        XCTAssertEqual(primeWeb.map(\.host), ["app.primevideo.com", "www.amazon.com"])
        XCTAssertEqual(queryValue("k", primeWeb.last), "The Matrix")
        XCTAssertEqual(queryValue("i", primeWeb.last), "instant-video")

        let max = ProviderLaunching.destination(for: P(id: 1899, name: "HBO Max"), movie: film)
        XCTAssertEqual(max.attempts { _ in true }.map(\.host), ["play.max.com"])
        XCTAssertEqual(max.hint, "Opens Max on the web")
        XCTAssertEqual(netflix.hint, "Opens the Netflix app or website")
    }

    func testTitleIsQueryEncoded() throws {
        let title = "A+B & C?"
        let destination = ProviderLaunching.destination(for: P(id: 8, name: "Netflix"), movie: movie(title))
        let web = try XCTUnwrap(destination.webURL)
        XCTAssertEqual(queryValue("q", web), title)
        XCTAssertFalse(web.absoluteString.contains(" "))
        let app = try XCTUnwrap(destination.appURL)
        XCTAssertEqual(app.scheme, "nflx")
        XCTAssertEqual(queryValue("q", app), title)

        let tubi = ProviderLaunching.destination(for: P(id: 73, name: "Tubi TV"), movie: movie(title))
        XCTAssertEqual(tubi.webURL?.host, "tubitv.com")
        XCTAssertTrue(tubi.webURL?.path.hasPrefix("/search/") == true)
        XCTAssertFalse(tubi.webURL?.absoluteString.contains(" ") == true)
    }

    func testUnknownProviderUsesTheMovieWatchLinkOrDoesNothing() {
        let explicit = "https://www.themoviedb.org/movie/603-the-matrix/watch?locale=US"
        let withLink = ProviderLaunching.destination(
            for: P(id: 7, name: "Fandango At Home"),
            movie: movie(link: explicit)
        )
        XCTAssertEqual(withLink.urls.map(\.absoluteString), [explicit])
        XCTAssertEqual(withLink.hint, "Opens all options on TMDB")
        XCTAssertEqual(withLink.attempts { _ in true }.map(\.absoluteString), [explicit])

        let synthesized = ProviderLaunching.destination(
            for: P(id: 7, name: "Fandango At Home"),
            movie: movie(tmdbId: 603)
        )
        XCTAssertEqual(
            synthesized.webURL?.absoluteString,
            "https://www.themoviedb.org/movie/603/watch?locale=US"
        )

        let nowhere = ProviderLaunching.destination(
            for: P(id: 7, name: "Fandango At Home"),
            movie: movie(tmdbId: nil)
        )
        XCTAssertTrue(nowhere.urls.isEmpty)
        XCTAssertTrue(nowhere.attempts { _ in true }.isEmpty)
        XCTAssertEqual(nowhere.hint, "No link for Fandango At Home")
    }

    func testQueriedSchemesMatchThePlistAndTheURLsWeBuild() throws {
        var emitted = Set<String>()
        let film = movie()
        let samples: [(Int, String)] = [
            (8, "Netflix"), (9, "Amazon Prime Video"), (192, "YouTube"),
            (337, "Disney Plus"), (15, "Hulu"), (350, "Apple TV"),
            (531, "Paramount Plus"), (73, "Tubi TV"), (7, "Fandango At Home"),
        ]
        for (id, name) in samples {
            let destination = ProviderLaunching.destination(for: P(id: id, name: name), movie: film)
            for url in destination.urls {
                let scheme = try XCTUnwrap(url.scheme)
                if scheme != "https" { emitted.insert(scheme) }
            }
        }
        XCTAssertEqual(emitted, Set(ProviderLaunching.queriedSchemes))

        let plistURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("MovieRouletteTuesday/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let declared = Set(try XCTUnwrap(plist["LSApplicationQueriesSchemes"] as? [String]))
        XCTAssertEqual(declared, Set(ProviderLaunching.queriedSchemes))
    }

    private func queryValue(_ name: String, _ url: URL?) -> String? {
        guard let url else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == name }?
            .value
    }
}
