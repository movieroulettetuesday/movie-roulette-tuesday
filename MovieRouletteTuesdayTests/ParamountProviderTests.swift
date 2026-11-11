import XCTest
@testable import MovieRouletteTuesday

final class ParamountProviderTests: XCTestCase {
    private typealias P = StreamingInfo.Provider

    private let fubo = P(id: 257, name: "fuboTV", priority: 10)
    private let premium = P(id: 2303, name: "Paramount Plus Premium", logo: "/premium.png", priority: 14)
    private let essential = P(id: 2616, name: "Paramount Plus Essential", priority: 15)
    private let amazon = P(id: 582, name: "Paramount+ Amazon Channel", priority: 26)
    private let roku = P(id: 633, name: "Paramount+ Roku Premium Channel", priority: 62)
    private let legacy = P(id: 531, name: "Paramount Plus", priority: 40)
    private let netflix = P(id: 8, name: "Netflix", priority: 1)
    private let netflixAds = P(id: 1796, name: "Netflix Standard with Ads", priority: 3)
    private let peacock = P(id: 386, name: "Peacock Premium", priority: 4)
    private let peacockPlus = P(id: 387, name: "Peacock Premium Plus", priority: 5)

    func testKeepsBestPriorityParamountAndLeavesOtherProviders() {
        // Essential is listed first; Premium still wins on priority.
        let providers = [essential, fubo, netflix, premium, amazon, netflixAds, roku, peacock, peacockPlus]
        let collapsed = StreamingCatalog.collapsingParamountPlusDuplicates(providers)
        XCTAssertEqual(collapsed.map(\.id), [fubo.id, netflix.id, premium.id, netflixAds.id, peacock.id, peacockPlus.id])
        XCTAssertEqual(collapsed.first { $0.id == premium.id }?.logo, "/premium.png")
    }

    func testSingleParamountAndEmptyListStayPut() {
        XCTAssertEqual(StreamingCatalog.collapsingParamountPlusDuplicates([premium, netflix]).map(\.id), [premium.id, netflix.id])
        XCTAssertEqual(StreamingCatalog.collapsingParamountPlusDuplicates([]).map(\.id), [])
    }

    func testLegacyParamountIdCollapsesWithNamedVariants() {
        let oddName = P(id: 531, name: "P+", priority: 2)
        let collapsed = StreamingCatalog.collapsingParamountPlusDuplicates([essential, oddName, legacy])
        XCTAssertEqual(collapsed.map(\.id), [oddName.id])
    }

    func testNameMatchIsCaseInsensitive() {
        let upper = P(id: 2303, name: "PARAMOUNT PLUS PREMIUM", priority: 9)
        let collapsed = StreamingCatalog.collapsingParamountPlusDuplicates([amazon, upper])
        XCTAssertEqual(collapsed.map(\.id), [upper.id])
    }

    func testEqualPriorityKeepsTheEarliestParamount() {
        let earlier = P(id: 2616, name: "Paramount Plus Essential", priority: 14)
        let later = P(id: 2303, name: "Paramount Plus Premium", priority: 14)
        XCTAssertEqual(
            StreamingCatalog.collapsingParamountPlusDuplicates([fubo, earlier, later]).map(\.id),
            [fubo.id, earlier.id]
        )
    }

    func testMovieWithSeveralParamountVariantsShowsOneTile() {
        // Fixed sample: Marathon Man (1976) as TMDB listed it before the Nov 9 2026 refresh,
        // with four Paramount+ variants mixed in with other services.
        let mgm = P(id: 34, name: "MGM Plus", priority: 20)
        let kanopy = P(id: 191, name: "Kanopy", priority: 30)
        let raw = [fubo, premium, essential, amazon, mgm, roku, kanopy]
        XCTAssertGreaterThan(raw.filter(Self.isParamount).count, 1)
        let collapsed = StreamingCatalog.collapsingParamountPlusDuplicates(raw)
        XCTAssertEqual(collapsed.filter(Self.isParamount).map(\.id), [premium.id])
        XCTAssertEqual(collapsed.map(\.id), [fubo.id, premium.id, mgm.id, kanopy.id])
        XCTAssertEqual(collapsed.first { $0.id == premium.id }?.logo, "/premium.png")
    }

    func testBundledCatalogShowsAtMostOneParamountPlusPerMovie() async throws {
        // Invariant over the real catalog only; it does not depend on which movies list Paramount+ today.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("MovieRouletteTuesday/Resources/movies.json")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("no movies.json") }
        let catalog = try await FileCatalogSource(fileURL: url).loadCatalog()
        XCTAssertFalse(catalog.movies.isEmpty)
        for movie in catalog.movies {
            guard let streaming = movie.streaming else { continue }
            let providers = streaming.stream + streaming.free
            let shown = StreamingCatalog.collapsingParamountPlusDuplicates(providers)
            XCTAssertLessThanOrEqual(shown.filter(Self.isParamount).count, 1, movie.id)
            XCTAssertEqual(
                shown.filter { !Self.isParamount($0) }.map(\.id),
                providers.filter { !Self.isParamount($0) }.map(\.id),
                movie.id
            )
        }
    }

    private static func isParamount(_ provider: StreamingInfo.Provider) -> Bool {
        provider.id == 531 || provider.name.lowercased().contains("paramount")
    }
}
