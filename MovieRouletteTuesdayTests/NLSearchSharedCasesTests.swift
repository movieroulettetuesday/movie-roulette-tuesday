import XCTest
@testable import MovieRouletteTuesday

/// The 32 shared cases in `mrt-shared/nl-search-test-cases.json` (a byte copy
/// in Fixtures/). The model's parse is STUBBED: each case's stub parse is its
/// `required` filter (plus a disallowed value for `validate` cases), because
/// the on-device model can't run reliably in the simulator. What is exact and
/// real: question detection, validation, the loose-compare rule, the list
/// switch, and `apply()` on a fixed fixture.
final class NLSearchSharedCasesTests: XCTestCase {
    struct Case {
        let id: String
        let question: String
        let outcome: String
        let required: [String: Any]
        let optional: [String: Any]
        let mustBeNull: [String]
        let disallowed: [String: [String]]
        let providerAcceptable: [String]?
        let titleFolded: String?
        let switchesTo: String
    }

    static func casesURL() -> URL {
        if let url = Bundle(for: NLSearchSharedCasesTests.self).url(forResource: "nl-search-test-cases", withExtension: "json") {
            return url
        }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/nl-search-test-cases.json")
    }

    static func loadCases() throws -> [Case] {
        let data = try Data(contentsOf: casesURL())
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])
        return cases.map { c in
            Case(
                id: c["id"] as? String ?? "",
                question: c["question"] as? String ?? "",
                outcome: c["outcome"] as? String ?? "",
                required: c["required"] as? [String: Any] ?? [:],
                optional: c["optional"] as? [String: Any] ?? [:],
                mustBeNull: c["mustBeNull"] as? [String] ?? [],
                disallowed: c["disallowedValues"] as? [String: [String]] ?? [:],
                providerAcceptable: c["providerAcceptable"] as? [String],
                titleFolded: c["titleFolded"] as? String,
                switchesTo: c["switchesTo"] as? String ?? ""
            )
        }
    }

    private var catalog: MovieCatalog!
    private var cases: [Case]!

    override func setUpWithError() throws {
        catalog = NLSearchFixture.catalog()
        cases = try Self.loadCases()
    }

    static func filter(from dict: [String: Any]) throws -> NLSearchFilter {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(NLSearchFilter.self, from: data)
    }

    static func dict(_ filter: NLSearchFilter) throws -> [String: Any] {
        let data = try JSONEncoder().encode(filter)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// The stub parse for a case: `required`, plus the first disallowed value
    /// of each field for `validate` cases, so validation has to remove it.
    static func stubParse(_ c: Case, includeOptional: Bool = false) throws -> NLSearchFilter {
        var d = c.required
        if includeOptional { d.merge(c.optional) { a, _ in a } }
        for (field, values) in c.disallowed { if let first = values.first { d[field] = first } }
        return try Self.filter(from: d)
    }

    private func same(_ a: Any, _ b: Any) -> Bool {
        if let x = a as? NSNumber, let y = b as? NSNumber { return x.doubleValue == y.doubleValue }
        if let x = a as? String, let y = b as? String { return x == y }
        return false
    }

    /// The README's loose-compare rule, applied to a validated parse.
    func looseMismatches(_ c: Case, _ filter: NLSearchFilter) throws -> [String] {
        let got = try Self.dict(filter)
        var problems: [String] = []
        for (key, want) in c.required {
            guard let value = got[key] else { problems.append("missing \(key)"); continue }
            if key == "provider", let ok = c.providerAcceptable, let s = value as? String {
                if !ok.contains(s) { problems.append("provider \(s)") }
            } else if key == "title", let folded = c.titleFolded, let s = value as? String {
                if !CatalogSearch.fold(s).contains(folded) { problems.append("title \(s)") }
            } else if !same(value, want) {
                problems.append("\(key)=\(value) want \(want)")
            }
        }
        for (key, value) in got where c.required[key] == nil {
            if let allowed = c.optional[key], same(value, allowed) { continue }
            problems.append("unexpected \(key)=\(value)")
        }
        for key in c.mustBeNull where got[key] != nil { problems.append("\(key) must be null") }
        for (key, values) in c.disallowed {
            if let s = got[key] as? String, values.contains(s) { problems.append("disallowed \(key)=\(s)") }
        }
        return problems
    }

    func testThirtyTwoSharedCasesLoaded() {
        XCTAssertEqual(cases.count, 32)
        XCTAssertEqual(Set(cases.map(\.id)).count, 32, "unique ids")
    }

    /// Questions reach the model; short title-like text and punctuation stay on CatalogSearch.
    func testQuestionDetectionMatchesOutcome() {
        let titles = catalog.movies.map(\.title)
        for c in cases {
            XCTAssertEqual(NLSearch.looksLikeQuestion(c.question, titles: titles), c.outcome != "empty-filter",
                           "\(c.id): \(c.question)")
        }
    }

    func testStubParsesValidateAndPassLooseCompare() throws {
        for c in cases {
            for withOptional in [false, true] {
                let parsed = NLSearch.validated(try Self.stubParse(c, includeOptional: withOptional), catalog: catalog)
                XCTAssertEqual(try looseMismatches(c, parsed), [], "\(c.id) optional=\(withOptional)")
                XCTAssertEqual(parsed.isEmpty, c.outcome == "empty-filter", "\(c.id) empty")
            }
        }
    }

    /// `validate` cases: every disallowed value is nulled, never reaching apply.
    func testEveryDisallowedValueIsNulled() throws {
        for c in cases where c.outcome == "validate" {
            for (field, values) in c.disallowed {
                for value in values {
                    var d = c.required
                    d[field] = value
                    let parsed = NLSearch.validated(try Self.filter(from: d), catalog: catalog)
                    XCTAssertNil(try Self.dict(parsed)[field], "\(c.id): \(field)=\(value)")
                }
            }
        }
    }

    func testSwitchDecisionMatchesEveryCaseFromBothLists() throws {
        for c in cases {
            let kind = NLSearch.validated(try Self.stubParse(c), catalog: catalog).kind
            for showing in NLSearch.List.allCases {
                let expected: NLSearch.SwitchDecision
                switch c.switchesTo {
                case "movies": expected = showing == .movies ? .stay : .switchTo(.movies)
                case "episodes": expected = showing == .episodes ? .stay : .switchTo(.episodes)
                default: expected = .stay
                }
                XCTAssertEqual(NLSearch.listSwitch(kind: kind, showing: showing), expected, "\(c.id) from \(showing)")
            }
        }
    }

    /// Exact apply() output on the fixture for both lists (movie ids in
    /// result order; episode guids in result order). Empty-filter cases never
    /// call apply.
    static let expected: [String: (movies: [String], episodes: [String])] = [
        "free-80s-horror-unwatched": (["hellraiser-1987"], ["ep-s4e40"]),
        "unrated-criterion": (["seven-samurai-1954", "the-shining-1980"], []),
        "watchlist-scifi": (["blade-runner-1982"], []),
        "rated-4-or-higher-on-my-services": (["alien-1979", "the-thing-1982"], ["ep-thing", "ep-alien"]),
        "s4e39": (["the-devils-rain-1975"], ["ep-s4e39"]),
        "season-4-episode-39-words": (["the-devils-rain-1975"], ["ep-s4e39"]),
        "filters-only-free-horror": (["hellraiser-1987", "the-devils-rain-1975", "the-evil-dead-1981", "the-thing-1982"],
                                     ["ep-s4e40", "ep-s4e39", "ep-thing"]),
        "year-range-1975-1985": (["alien-1979", "blade-runner-1982", "the-devils-rain-1975", "the-evil-dead-1981",
                                  "the-shining-1980", "the-thing-1982"],
                                 ["ep-s4e39", "ep-thing", "ep-alien"]),
        "free-only-tonight": (["hellraiser-1987", "seven-samurai-1954", "the-devils-rain-1975", "the-evil-dead-1981",
                               "the-room-2003", "the-thing-1982"],
                              ["ep-s4e40", "ep-s4e39", "ep-thing"]),
        "unwatched-movies": (["blade-runner-1982", "die-hard-1988", "eternal-sunshine-2004", "hellraiser-1987",
                              "seven-samurai-1954", "the-devils-rain-1975", "the-shining-1980", "the-thing-2011", "titanic-1997"],
                             ["ep-s4e40", "ep-s4e39"]),
        "unrated-movies": (["die-hard-1988", "eternal-sunshine-2004", "hellraiser-1987", "seven-samurai-1954",
                            "the-evil-dead-1981", "the-shining-1980", "the-thing-2011", "titanic-1997"],
                           ["ep-s4e40"]),
        "rating-range-3-to-4-5": (["alien-1979", "blade-runner-1982", "heathers-1989", "the-devils-rain-1975"],
                                  ["ep-s4e39", "ep-alien"]),
        "unknown-genre-animation": (["alien-1979", "blade-runner-1982", "die-hard-1988", "eternal-sunshine-2004",
                                     "heathers-1989", "hellraiser-1987", "pulp-fiction-1994", "seven-samurai-1954",
                                     "the-devils-rain-1975", "the-evil-dead-1981", "the-godfather-1972", "the-room-2003",
                                     "the-shining-1980", "the-thing-1982", "the-thing-2011", "titanic-1997"],
                                    ["ep-s4e40", "ep-s4e39", "ep-bonus", "ep-thing", "ep-alien"]),
        "unknown-provider-blockbuster": (["hellraiser-1987", "the-devils-rain-1975", "the-evil-dead-1981",
                                          "the-shining-1980", "the-thing-1982", "the-thing-2011"],
                                         ["ep-s4e40", "ep-s4e39", "ep-thing"]),
        "provider-movies-on-shudder": (["the-devils-rain-1975", "the-thing-1982"], ["ep-s4e39", "ep-thing"]),
        "provider-free-on-tubi": (["hellraiser-1987", "the-evil-dead-1981", "the-room-2003", "the-thing-1982"],
                                  ["ep-s4e40", "ep-thing"]),
        "provider-pluto": (["the-devils-rain-1975", "the-evil-dead-1981"], ["ep-s4e39"]),
        "provider-disney-plus": (["titanic-1997"], []),
        "provider-hbo-max": (["alien-1979", "pulp-fiction-1994"], ["ep-alien"]),
        "provider-netflix-unwatched": (["blade-runner-1982", "eternal-sunshine-2004", "the-thing-2011"], []),
        "find-the-thing": (["the-thing-1982", "the-thing-2011"], ["ep-thing"]),
        "s4e39-with-title": (["the-devils-rain-1975"], ["ep-s4e39"]),
        "dark-comedy-on-my-services": (["heathers-1989"], []),
        "listener-picks-unwatched": (["eternal-sunshine-2004"], []),
        "love-hurts-90s": (["titanic-1997"], []),
        "prestige-rated-5": (["the-godfather-1972"], []),
        "switch-to-episodes-about-the-thing": (["the-thing-1982", "the-thing-2011"], ["ep-thing"]),
        "switch-to-movies-unwatched": (["blade-runner-1982", "die-hard-1988", "eternal-sunshine-2004", "hellraiser-1987",
                                        "seven-samurai-1954", "the-devils-rain-1975", "the-shining-1980", "the-thing-2011", "titanic-1997"],
                                       ["ep-s4e40", "ep-s4e39"]),
        "stay-put-horror-unwatched": (["hellraiser-1987", "the-devils-rain-1975", "the-shining-1980", "the-thing-2011"],
                                      ["ep-s4e40", "ep-s4e39"]),
    ]

    func testApplyMatchesExactlyForEveryCase() throws {
        let ratings = NLSearchFixture.ratings()
        let episodes = NLSearchFixture.episodes()
        let byGUID = Dictionary(uniqueKeysWithValues: episodes.map { ($0.guid, $0) })
        var covered = 0
        for c in cases {
            let filter = NLSearch.validated(try Self.stubParse(c), catalog: catalog)
            if c.outcome == "empty-filter" {
                XCTAssertTrue(filter.isEmpty, c.id)
                XCTAssertNil(Self.expected[c.id], "\(c.id) must not have apply output")
                continue
            }
            guard let want = Self.expected[c.id] else { XCTFail("no expectation for \(c.id)"); continue }
            covered += 1
            let movies = NLSearch.apply(filter, toMovies: catalog.movies, catalog: catalog, ratings: ratings,
                                        services: NLSearchFixture.services, episodesByGUID: byGUID).movies.map(\.id)
            let eps = NLSearch.apply(filter, toEpisodes: episodes, catalog: catalog, ratings: ratings,
                                     services: NLSearchFixture.services, calendar: NLSearchFixture.utc).map(\.guid)
            XCTAssertEqual(movies, want.movies, "\(c.id) movies")
            XCTAssertEqual(eps, want.episodes, "\(c.id) episodes")
            if !filter.hasSearchText {
                // Filters-only: CatalogSearch is never called with an empty query.
                XCTAssertNil(filter.searchText, c.id)
            }
        }
        XCTAssertEqual(covered, 29)
    }
}
