// Movie Roulette Tuesday: shared test-vector generator.
// Runs the iOS RouletteCore sources (copied unchanged from the iOS repo) and
// writes the expected outputs to mrt-shared/test-vectors/*.json.
// Usage: tools/vector-gen/gen.sh   (never edit the generated JSON by hand)
import Foundation
import CryptoKit
import MRTCore

typealias J = [String: Any]

/// Matches QuickSpin / Siri default when no offline listener bulk is loaded.
/// Empty map ⇒ InfamousSelection treats every movie as unrated (weight 2.5).
/// For synthetic "infamous" fixture movies (d-2, b-1) we assign a low average
/// so jackpot weighting still prefers them the way the old isInfamous flag did.
let fixtureListenerAverages: [String: Double] = ["d-2": 0.5, "b-1": 0.5]

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
let iosRoot = URL(fileURLWithPath: CommandLine.arguments[2])
let iosCommit = CommandLine.arguments[3]

// MARK: helpers
func num(_ d: Double) -> Any {
    if d.isNaN { return "NaN" }
    if d.isInfinite { return d > 0 ? "Infinity" : "-Infinity" }
    return d
}
func opt(_ v: Any?) -> Any { v ?? NSNull() }
let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.timeZone = TimeZone(identifier: "UTC"); return f }()
func date(_ d: Date?) -> Any { d.map { iso.string(from: $0) } ?? NSNull() }
func parseISO(_ s: String) -> Date { iso.date(from: s)! }
var utc: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
func write(_ name: String, _ obj: J) {
    var o = obj
    o["_generated"] = ["by": "tools/vector-gen (runs iOS RouletteCore unchanged)", "iosCommit": iosCommit,
                       "note": "Do not edit by hand. Non-finite numbers are encoded as the strings \"NaN\", \"Infinity\", \"-Infinity\". Compare floats with abs tolerance 1e-9 unless a case says otherwise. Dates are ISO-8601 UTC."]
    let data = try! JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    try! data.write(to: outDir.appendingPathComponent(name))
    print("wrote \(name)")
}
func movie(_ id: String, _ cats: [String], infamous: Bool = false, genre: String = "Drama", eps: [String] = [], epTitle: String? = nil, year: Int = 2000) -> Movie {
    Movie(id: id, title: "Movie \(id)", year: year, genre: genre, categories: cats, episodeIds: eps, episodeTitle: epTitle)
}
func catJSON(_ c: MovieCatalog) -> J {
    ["schemaVersion": c.schemaVersion,
     "categories": c.categories.map { ["id": $0.id, "name": $0.name, "fullName": opt($0.fullName), "colorHex": $0.colorHex, "weight": opt($0.weight), "movieIds": $0.movieIds] as J },
     "movies": c.movies.map { ["id": $0.id, "title": $0.title, "year": $0.year, "genre": $0.genre, "categories": $0.categories, "episodeIds": $0.episodeIds, "episodeTitle": opt($0.episodeTitle), "isInfamous": false /* legacy; jackpot uses listener averages */] as J }]
}
func spinJSON(_ s: SpinResult) -> J { ["movieId": s.movieId, "categoryId": s.categoryId, "timestamp": date(s.timestamp)] }

// Fixture catalogs (same shape as Android main RouletteFixtures).
let fixtureCats = ["a", "b", "c", "d"]
let fixtureCatalog: MovieCatalog = {
    let colors = ["#C1121F", "#7B2CBF", "#E9C46A", "#2A9D8F"]
    let movies = fixtureCats.flatMap { c in [
        Movie(id: "\(c)-1", title: "Movie \(c) 1", year: 2001, genre: "Drama", categories: [c], episodeIds: ["Buzzsprout-1"], episodeTitle: "Ep \(c)"),
        Movie(id: "\(c)-2", title: "Movie \(c) 2", year: 2002, genre: "Drama", categories: [c]),
    ] }
    return MovieCatalog(schemaVersion: 2, categories: fixtureCats.enumerated().map { i, c in
        RouletteCategory(id: c, name: c.uppercased(), fullName: "Category \(c.uppercased())", colorHex: colors[i], movieIds: ["\(c)-1", "\(c)-2"])
    }, movies: movies)
}()
let infamousCatalog: MovieCatalog = {
    var c = fixtureCatalog
    /* isInfamous removed: jackpot bias via fixtureListenerAverages for d-2/b-1 */
    _ = fixtureListenerAverages
    return c
}()
let bundledData = try! Data(contentsOf: iosRoot.appendingPathComponent("MovieRouletteTuesday/Resources/movies.json"))
let bundled = try! MovieCatalog.decode(from: bundledData).deduplicated()

struct CountingRNG: RandomNumberGenerator {
    var base: SeededRandomNumberGenerator; var draws = 0
    init(seed: UInt64) { base = SeededRandomNumberGenerator(seed: seed) }
    mutating func next() -> UInt64 { draws += 1; return base.next() }
}

// MARK: 1. Catalog
func evalCatalog(_ json: String) -> J {
    guard let c = try? MovieCatalog.decode(from: Data(json.utf8)) else { return ["decodes": false] }
    var r: J = ["decodes": true, "schemaVersion": c.schemaVersion, "movieIds": c.movies.map(\.id), "categoryIds": c.categories.map(\.id),
                "validationIssues": c.validationIssues(), "showHosts": c.showInfo.hosts, "hasShowBlock": c.show != nil]
    do { try CatalogValidator.validate(c); r["validator"] = "ok" } catch let e as CatalogValidationError {
        switch e { case .unsupportedSchema: r["validator"] = "unsupportedSchema"; case .empty: r["validator"] = "empty"; case .inconsistent: r["validator"] = "inconsistent" }
    } catch { r["validator"] = "error" }
    let d = c.deduplicated()
    r["deduplicated"] = ["movieIds": d.movies.map(\.id), "categoryIds": d.categories.map(\.id), "firstMovieCategories": d.movies.first?.categories ?? []]
    r["movies"] = c.movies.map { m -> J in
        ["id": m.id, "episodeIds": m.episodeIds, "isInfamous": false /* legacy; jackpot uses listener averages */, "tmdbId": opt(m.tmdbId), "hostRating": opt(m.hostRating),
         "streaming": m.streaming.map { s -> J in ["region": s.region, "stream": s.stream.map(\.name), "free": s.free.map(\.name), "rent": s.rent.map(\.name), "buy": s.buy.map(\.name), "isEmpty": s.isEmpty] } ?? NSNull(),
         "subtitle": c.subtitle(for: m)]
    }
    r["categoryDisplayNames"] = c.categories.map(\.displayName)
    return r
}
let minimal = ##"{"categories":[{"id":"c1","name":"One","colorHex":"#112233","movieIds":["m1"]}],"movies":[{"id":"m1","title":"Movie","year":1999,"genre":"Drama","categories":["c1"]}]}"##
func minimalWith(schema: Int = 2, color: String = "#112233", title: String = "Movie") -> String {
    ##"{"schemaVersion":\##(schema),"_note":"ignored","categories":[{"id":"c1","name":"One","colorHex":"\##(color)","movieIds":["m1"]}],"movies":[{"id":"m1","title":"\##(title)","year":1999,"genre":"Drama","categories":["c1"]}]}"##
}
let catalogCases: [(String, String, String)] = [
    ("minimal-defaults", minimal, "android-main:CatalogJsonTest.decodesMinimalJsonWithDefaults"),
    ("unknown-keys-ignored", minimalWith(), "android-main:CatalogJsonTest.ignoresUnknownKeysLikeNote"),
    ("schema-3-unsupported", minimalWith(schema: 3), "android-main:CatalogValidationTest.rejectsUnsupportedSchemaEmptyAndInconsistent"),
    ("schema-0-unsupported", minimalWith(schema: 0), "ios"),
    ("schema-1-ok", minimalWith(schema: 1), "ios"),
    ("empty-lists", ##"{"categories":[],"movies":[]}"##, "android-main:CatalogValidationTest.rejectsUnsupportedSchemaEmptyAndInconsistent"),
    ("bad-color-short", minimalWith(color: "#12"), "android-main:CatalogValidationTest.rejectsUnsupportedSchemaEmptyAndInconsistent"),
    ("color-8-digit-ok", minimalWith(color: "#11223380"), "ios"),
    ("color-no-hash-ok", minimalWith(color: "112233"), "ios"),
    ("color-named-bad", minimalWith(color: "red"), "ios"),
    ("find-problems", ##"{"categories":[{"id":"a","name":"a","colorHex":"#112233","movieIds":["m1","ghost"]},{"id":"b","name":"b","colorHex":"red","movieIds":[]},{"id":"a","name":"a","colorHex":"#112233","movieIds":["m1"]}],"movies":[{"id":"m1","title":"m1","year":2000,"genre":"Drama","categories":["a","nowhere"]},{"id":"m1","title":"m1","year":2000,"genre":"Drama","categories":["a"]},{"id":"m2","title":"m2","year":2000,"genre":"Drama","categories":["b"]}]}"##, "android-main:CatalogValidationTest.findsProblems"),
    ("one-sided-link", ##"{"categories":[{"id":"a","name":"A","colorHex":"#112233","movieIds":["m1","m2"]}],"movies":[{"id":"m1","title":"T","year":2000,"genre":"Drama","categories":["a"]},{"id":"m2","title":"T2","year":2000,"genre":"Drama"}]}"##, "ios"),
    ("malformed-optional-fields", ##"{"categories":[{"id":"c1","name":"One","colorHex":"#112233","movieIds":["m1"]}],"movies":[{"id":"m1","title":"M","year":1999,"genre":"Drama","categories":["c1"],"tmdbId":"not-a-number","streaming":{"stream":"oops","rent":[{"id":2,"name":"Apple"}]}}]}"##, "android-main:CatalogJsonTest.malformedNewFieldsNeverBreakTheCatalog"),
    ("missing-title", ##"{"categories":[],"movies":[{"id":"m1","year":1999,"genre":"Drama"}]}"##, "android-main:CatalogJsonTest.missingRequiredKeyFails"),
    ("year-as-string", ##"{"categories":[],"movies":[{"id":"m1","title":"T","year":"1999","genre":"Drama"}]}"##, "android-main:CatalogJsonTest.wrongTypeFails"),
    ("year-fractional", ##"{"categories":[],"movies":[{"id":"m1","title":"T","year":1999.5,"genre":"Drama"}]}"##, "android-main:CatalogJsonTest.fractionalYearFails"),
    ("year-integral-double", ##"{"categories":[{"id":"c1","name":"One","colorHex":"#112233","movieIds":["m1"]}],"movies":[{"id":"m1","title":"T","year":1999.0,"genre":"Drama","categories":["c1"]}]}"##, "ios (Android CatalogJson comment claims 1983.0 is accepted)"),
    ("garbage", "<html>rate limited</html>", "android-main:CatalogJsonTest.garbageFails"),
    ("missing-categories-key", ##"{"movies":[]}"##, "ios"),
    ("isInfamous-wrong-type", ##"{"categories":[{"id":"c1","name":"One","colorHex":"#112233","movieIds":["m1"]}],"movies":[{"id":"m1","title":"T","year":1999,"genre":"Drama","categories":["c1"],"isInfamous":"yes"}]}"##, "ios"),
    ("isInfamous-true-and-weight", ##"{"categories":[{"id":"c1","name":"One","colorHex":"#112233","weight":2.5,"movieIds":["m1"]}],"movies":[{"id":"m1","title":"T","year":1999,"genre":"Drama","categories":["c1"],"isInfamous":true,"tmdbId":null}]}"##, "ios"),
    ("show-block-missing-hosts", ##"{"show":{"name":"X"},"categories":[{"id":"c1","name":"One","colorHex":"#112233","movieIds":["m1"]}],"movies":[{"id":"m1","title":"T","year":1999,"genre":"Drama","categories":["c1"]}]}"##, "ios"),
    ("show-block-full", ##"{"show":{"name":"X","hosts":["A","B"]},"categories":[{"id":"c1","name":"One","colorHex":"#112233","movieIds":["m1"]}],"movies":[{"id":"m1","title":"T","year":1999,"genre":"Drama","categories":["c1"]}]}"##, "ios"),
    ("posterURL-empty-string", ##"{"categories":[{"id":"c1","name":"One","colorHex":"#112233","movieIds":["m1"]}],"movies":[{"id":"m1","title":"T","year":1999,"genre":"Drama","categories":["c1"],"posterURL":""}]}"##, "ios"),
    ("weight-as-string", ##"{"categories":[{"id":"c1","name":"One","colorHex":"#112233","weight":"2","movieIds":["m1"]}],"movies":[{"id":"m1","title":"T","year":1999,"genre":"Drama","categories":["c1"]}]}"##, "ios"),
    ("dedupe-first-wins", ##"{"categories":[{"id":"a","name":"a","colorHex":"#112233","movieIds":["m1"]},{"id":"a","name":"a","colorHex":"#112233","movieIds":["x"]}],"movies":[{"id":"m1","title":"m1","year":2000,"genre":"Drama","categories":["a"]},{"id":"m1","title":"m1","year":2000,"genre":"Drama","categories":[]}]}"##, "android-main:CatalogValidationTest.deduplicatedKeepsFirst"),
    ("subtitle-genre-fallback", ##"{"categories":[{"id":"c1","name":"One","colorHex":"#112233","movieIds":["m1"]}],"movies":[{"id":"m1","title":"T","year":1999,"genre":"Drama","categories":["c1","ghost"]},{"id":"m2","title":"T","year":2001,"genre":"Comedy"}]}"##, "android-main:CatalogJsonTest.subtitleUsesCategoryNamesElseGenre (extended)"),
]
var catalogOut: [J] = catalogCases.map { name, json, src in ["name": name, "source": src, "input": json, "expected": evalCatalog(json)] }

func hexCase(_ s: String) -> J {
    guard let h = HexColor(s) else { return ["input": s, "valid": false] }
    return ["input": s, "valid": true, "rgba255": [h.red, h.green, h.blue, h.alpha].map { Int(($0 * 255).rounded()) },
            "relativeLuminance": h.relativeLuminance, "prefersDarkText": h.prefersDarkText, "hexString": h.hexString]
}
let hexInputs = ["#FF8000", "11223380", "#GG0000", "#FFF", "#E9C46A", "#7B2CBF", " #2A9D8F ", "#c1121f", "", "#", "#1122334", "#FFFFFF", "#000000", "#00A6FB"]
let paletteCases: [J] = [("cat-horror", "#C1121F"), ("cat-listener", nil), ("cat-new", "#FF0000"), ("cat-new2", "#00A6FB"), ("cat-unknown", nil), ("cat-unknown", "nope"), ("zzz", nil)].map { (id: String, hex: String?) in
    ["categoryId": id, "catalogHex": opt(hex), "displayHex": CategoryPalette.hex(forCategoryId: id, catalogHex: hex)]
}
let radial: [J] = ["#C25B5E", "#4D97C2", "bad"].map { ["input": $0, "stops": CategoryPalette.radialStops($0)] }
let sha = { (d: Data) -> String in
    SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
}
func posterCase(_ poster: String) -> J {
    let lit = String(data: try! JSONSerialization.data(withJSONObject: [poster], options: [.withoutEscapingSlashes]), encoding: .utf8)!.dropFirst().dropLast()
    let json = ##"{"categories":[{"id":"c1","name":"One","colorHex":"#112233","movieIds":["m1"]}],"movies":[{"id":"m1","title":"T","year":1999,"genre":"Drama","categories":["c1"],"posterURL":"## + lit + "}]}"
    let c = try? JSONDecoder().decode(MovieCatalog.self, from: Data(json.utf8))
    return ["posterURL": poster, "input": json, "expected": ["decodes": c != nil, "posterURL": opt(c?.movies.first?.posterURL?.absoluteString),
            "artworkUsable": opt(ArtworkResolver.usableURL(c?.movies.first?.posterURL)?.absoluteString)]]
}
let posterDecoding: J = [
    "description": "SPEC §1.1 / E4: on current Foundation only an EMPTY posterURL fails decoding (and so rejects the whole document). Other strings are percent-encoded or become relative URLs, which ArtworkResolver then drops. Generated on Linux swift-corelibs; iOS 17+ URL(string:) is expected to match (unverified on device). Android MUST fail on the empty string and MUST NOT fail on the other cases; for those, the stored posterURL may differ in encoding as long as artworkUsable (null vs non-null) matches.",
    "cases": ["", "a b", "https://ex.com/é.jpg", "not a url", "https://ex.com/poster.jpg", "http://ex.com/p.jpg"].map(posterCase),
]
write("catalog.json", [
    "description": "movies.json decoding + validation (SPEC §1.1-1.2). For each case decode `input`; when expected.decodes is false the decoder must throw. validator = result of CatalogValidator.validate on the decoded catalog. validationIssues are exact strings, sorted.",
    "cases": catalogOut, "posterURLDecoding": posterDecoding,
    "hexColor": ["description": "HexColor parsing (SPEC §1.2 HexColor). rgba255 = round(component*255).", "cases": hexInputs.map(hexCase)],
    "categoryPalette": ["description": "CategoryPalette.hex(forCategoryId:catalogHex:) = the colour every surface draws (SPEC §1.4).", "cases": paletteCases, "radialStops": radial],
    "bundled": ["path": "MovieRouletteTuesday/Resources/movies.json", "sha256": sha(bundledData), "movieCount": bundled.movies.count,
                "categoryIds": bundled.categories.map(\.id), "infamousCount": 0 /* isInfamous removed; jackpotCandidates = all movies */,
                "validationIssues": bundled.validationIssues(), "hosts": bundled.showInfo.hosts,
                "candidateCounts": Dictionary(uniqueKeysWithValues: bundled.categories.map { ($0.id, MovieSelector().candidates(for: $0, in: bundled).count) })],
])

// MARK: 2. RSS
func epJSON(_ e: PodcastEpisode) -> J {
    ["guid": e.guid, "title": e.title, "pubDate": date(e.pubDate), "link": opt(e.link?.absoluteString), "season": opt(e.season), "episode": opt(e.episode),
     "episodeType": opt(e.episodeType), "summary": e.summary, "imageURL": opt(e.imageURL?.absoluteString), "fanMailURL": opt(e.fanMailURL?.absoluteString),
     "seasonEpisodeLabel": opt(e.seasonEpisodeLabel)]
}
func feedCase(_ name: String, _ xml: String) -> J {
    do {
        let f = try RSSFeedParser.parse(string: xml)
        return ["name": name, "input": xml, "expected": ["ok": true, "title": f.title, "artworkURL": opt(f.artworkURL?.absoluteString), "episodes": f.episodes.map(epJSON)]]
    } catch let e as RSSFeedError {
        return ["name": name, "input": xml, "expected": ["ok": false, "error": e == .emptyDocument ? "emptyDocument" : "malformed"]]
    } catch { return ["name": name, "input": xml, "expected": ["ok": false, "error": "malformed"]] }
}
let fixtureXML = try! String(contentsOf: iosRoot.appendingPathComponent("MovieRouletteTuesdayTests/Fixtures/feed-snippet.xml"), encoding: .utf8)
let rssHead = ##"<?xml version="1.0" encoding="UTF-8"?><rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" xmlns:content="http://purl.org/rss/1.0/modules/content/"><channel><title>T</title>"##
var feeds: [J] = [
    feedCase("buzzsprout-fixture (MovieRouletteTuesdayTests/Fixtures/feed-snippet.xml)", fixtureXML),
    feedCase("empty-document", ""),
    { var c = feedCase("not-xml", "<html><body>oops"); c["platformNote"] = "OPEN QUESTION Q2: swift-corelibs XMLParser (Linux, where this vector was generated) accepts this unterminated document and yields 0 episodes; Apple XMLParser on device may throw instead. Either way: no episodes. Do not treat this case as strict until confirmed on iOS."; c["acceptable"] = [["ok": false, "error": "malformed"], ["ok": true, "episodes": [Any]()]]; return c }(),
    feedCase("empty-channel", ##"<?xml version="1.0"?><rss><channel><title>Empty</title></channel></rss>"##),
    feedCase("guid-falls-back-to-link; untitled item dropped; duplicate guid keeps first", rssHead + ##"<item><title>A</title><link>https://example.com/a</link></item><item><guid>g1</guid></item><item><title>B</title><guid>g2</guid></item><item><title>B again</title><guid>g2</guid></item></channel></rss>"##),
    feedCase("non-integer episode ignored; season parsed; type kept", rssHead + ##"<item><title>X</title><guid>g</guid><itunes:season>3</itunes:season><itunes:episode>12a</itunes:episode><itunes:episodeType>bonus</itunes:episodeType></item></channel></rss>"##),
    feedCase("channel image fallback to <image><url>; item image non-http ignored", rssHead + ##"<image><url>https://example.com/show.jpg</url><title>ignored</title></image><item><title>X</title><guid>g</guid><itunes:image href="ftp://example.com/x.jpg"/></item></channel></rss>"##),
    feedCase("html entities, tags and whitespace collapsed; longest notes win", rssHead + ##"<item><title>X</title><guid>g</guid><description><![CDATA[<p>Tom &amp; Jerry&nbsp;&quot;rule&quot;</p>   <p>ok</p>]]></description><itunes:summary>short</itunes:summary></item></channel></rss>"##),
    feedCase("fan mail anchor without fan_mail href but label", rssHead + ##"<item><title>X</title><guid>g</guid><description><![CDATA[<a href="https://example.com/write?a=1&amp;b=2">Send us Fan Mail</a> Hello]]></description></item></channel></rss>"##),
    feedCase("content:encoded AFTER description is ignored (first HTML field wins; SPEC §2.2 / E8)", rssHead + ##"<item><title>X</title><guid>g</guid><description>short desc</description><content:encoded><![CDATA[<p>a much longer content encoded body that would win if it counted</p>]]></content:encoded></item></channel></rss>"##),
    feedCase("content:encoded BEFORE description is used (and wins over a shorter summary)", rssHead + ##"<item><title>X</title><guid>g</guid><content:encoded><![CDATA[<p>a much longer content encoded body that wins</p>]]></content:encoded><description>short desc</description><itunes:summary>tiny</itunes:summary></item></channel></rss>"##),
    feedCase("itunes:summary longer than description wins", rssHead + ##"<item><title>X</title><guid>g</guid><description>short desc</description><itunes:summary>a longer itunes summary text</itunes:summary></item></channel></rss>"##),
    { var c = feedCase("truncated rss (android-main RssFeedParserTest.emptyAndBrokenInput)", "<rss><channel><item>"); c["source"] = "android-main:RssFeedParserTest.emptyAndBrokenInput"; c["platformNote"] = "OPEN QUESTION Q2: swift-corelibs XMLParser (Linux) yields ok with 0 episodes; Android main throws RssFeedException; Apple XMLParser may throw. Either way: no episodes. See DISCREPANCIES D11."; c["acceptable"] = [["ok": false, "error": "malformed"], ["ok": true, "episodes": [Any]()]]; return c }(),
    feedCase("date variants", rssHead + ##"<item><title>1</title><guid>d1</guid><pubDate>Tue, 06 Oct 2026 00:00:00 -0400</pubDate></item><item><title>2</title><guid>d2</guid><pubDate>06 Oct 2026 04:00:00 GMT</pubDate></item><item><title>3</title><guid>d3</guid><pubDate>Tue, 06 Oct 2026 04:00 +0000</pubDate></item><item><title>4</title><guid>d4</guid><pubDate>2026-10-06</pubDate></item><item><title>5</title><guid>d5</guid><pubDate>Tue, 06 Oct 2026 00:00:00 EST</pubDate></item></channel></rss>"##),
]
if let p = ProcessInfo.processInfo.environment["MRT_ANDROID_FEED_SAMPLE"], let xml = try? String(contentsOfFile: p, encoding: .utf8) {
    var c = feedCase("android feed-sample.rss (Android main app/src/test/resources/episodes/feed-sample.rss)", xml)
    c["source"] = "android-main:RssFeedParserTest.parsesLiveFeedSampleWithEdgeCases"
    feeds.append(c)
}
let dateCases: [J] = ["Tue, 06 Oct 2026 00:00:00 EDT", " Tue, 06 Oct 2026 04:00 +0000 ", "Tue, 06 Oct 2026 00:00:00 -0400", "06 Oct 2026 04:00:00 GMT", "Tue, 06 Oct 2026 04:00 +0000", "Tue, 06 Oct 2026 00:00:00 EST", " Mon, 05 Oct 2026 23:59:59 +0000 ", "2026-10-06", "", "garbage"].map { ["input": $0, "expected": date(RSSFeedParser.parseDate($0))] }
let fanStrip: [J] = ["Send us Fan Mail Hi there", "send us fanmail: Hi", "We read fan mail today", "Send us Fan Mail", "  SEND US FAN MAIL — | Hello  ", "Send us fan mail!Hi"].map { ["input": $0, "expected": ShowNotes.strippingFanMail($0)] }
let fanURL: [J] = ["<p>No link</p>", ##"<a href="https://example.com/x">Other</a>"##, ##"<a target="_blank" href="https://www.buzzsprout.com/2117292/fan_mail/new">Send us Fan Mail</a>"##, ##"<a href='javascript:alert(1)'>Fan Mail</a>"##, ##"<a href="https://example.com/fan_mail?x=1&amp;y=2">write</a>"##].map { ["input": $0, "expected": opt(ShowNotes.fanMailURL(inHTML: $0)?.absoluteString)] }

// Episode <-> movie matching
let matchCatalog = MovieCatalog(categories: [RouletteCategory(id: "c", name: "C", colorHex: "#112233", movieIds: ["m1", "m2", "m3", "m4"])], movies: [
    Movie(id: "m1", title: "One", year: 1983, genre: "Drama", categories: ["c"], episodeIds: ["Buzzsprout-19913482"], episodeTitle: "The Outsiders"),
    Movie(id: "m2", title: "Two", year: 1990, genre: "Drama", categories: ["c"], episodeIds: ["Buzzsprout-1", "Buzzsprout-2"], episodeTitle: "Double Feature"),
    Movie(id: "m3", title: "Three", year: 1991, genre: "Drama", categories: ["c"], episodeIds: ["Buzzsprout-2", "Buzzsprout-3", "Buzzsprout-4"], episodeTitle: "Triple"),
    Movie(id: "m4", title: "Four", year: 1992, genre: "Drama", categories: ["c"], episodeIds: ["sample-ep-6", "sample-ep-7"]),
])
let feedForMatch = try! RSSFeedParser.parse(string: fixtureXML).episodes + [PodcastEpisode(guid: "Buzzsprout-2", title: "Second", season: 1, episode: 2)]
let byGUID = PodcastEpisode.byGUID(feedForMatch)
let matchCases: [J] = ["Buzzsprout-19913482", "Buzzsprout-19877460", "Buzzsprout-2", "buzzsprout-19913482", " Buzzsprout-1", "sample-ep-6"].map { ["guid": $0, "movieId": opt(matchCatalog.movie(forEpisodeGuid: $0)?.id)] }
let discussed: [J] = matchCatalog.movies.flatMap { m -> [J] in [
    ["movieId": m.id, "feedLoaded": false, "expected": EpisodeLabel.discussedText(for: m)],
    ["movieId": m.id, "feedLoaded": true, "expected": EpisodeLabel.discussedText(for: m, episodesByGUID: byGUID)],
] } + [["movieId": "no-episodes", "feedLoaded": false, "expected": EpisodeLabel.discussedText(for: Movie(id: "x", title: "X", year: 1, genre: "g"))]]
let totals = EpisodeTotals(episodes: feedForMatch, catalog: matchCatalog)
let spotify: [J] = ["S4 · E34 – Romeo + Juliet 🎬", "The Outsiders", "Episode 12: Movie Roulette Tuesday Special", "Buzzsprout-123", "#34 | Don’t Look Now", "Ep. 7 - Jean-Claude's Picks?"].map { ["input": $0, "query": PodcastLinks.spotifySearchQuery(episodeTitle: $0), "url": opt(PodcastLinks.spotifySearch(episodeTitle: $0)?.absoluteString)] }
// Android main cross-check: inputs + Android's asserted outputs, re-run on iOS.
func xc(_ src: String, _ input: Any, _ android: Any?, _ ios: Any?) -> J {
    let a = android ?? NSNull(), i = ios ?? NSNull()
    func canon(_ v: Any) -> String {
        let d = try! JSONSerialization.data(withJSONObject: [v], options: [.sortedKeys, .fragmentsAllowed])
        return String(decoding: d, as: UTF8.self).replacingOccurrences(of: ".0]", with: "]")
    }
    let agrees = canon(a) == canon(i)
    return ["source": "android-main:" + src, "input": input, "androidExpected": a, "expected": i, "agrees": agrees]
}
let spotifyAndroid: [(String, String)] = [
    ("The Outsiders", "The Outsiders Movie Roulette Tuesday"), ("Palmer Rockey's SCARLET WARNING 666", "Palmer Rockey's SCARLET WARNING 666 Movie Roulette Tuesday"),
    ("Romeo + Juliet", "Romeo Juliet Movie Roulette Tuesday"), ("Rock & Rule", "Rock Rule Movie Roulette Tuesday"), ("Mad Max: Fury Road", "Mad Max Fury Road Movie Roulette Tuesday"),
    ("O Brother, Where Art Thou?", "O Brother Where Art Thou Movie Roulette Tuesday"), ("Kon-Tiki", "Kon-Tiki Movie Roulette Tuesday"), ("Cry-Baby", "Cry-Baby Movie Roulette Tuesday"),
    ("π", "π Movie Roulette Tuesday"), ("Season 3: Year In Review", "Season 3 Year In Review Movie Roulette Tuesday"), ("What is Movie Roulette Tuesday?", "What is Movie Roulette Tuesday"),
    ("S4 · E34 – The Outsiders", "The Outsiders Movie Roulette Tuesday"), ("S4E34: The Outsiders 🎬", "The Outsiders Movie Roulette Tuesday"), ("Ep. 11 - Romeo + Juliet", "Romeo Juliet Movie Roulette Tuesday"),
    ("Episode 34: The Outsiders", "The Outsiders Movie Roulette Tuesday"), ("#29 | Crash", "Crash Movie Roulette Tuesday"),
    ("  Palmer Rockey\u{2019}s SCARLET WARNING 666 🔥 ", "Palmer Rockey's SCARLET WARNING 666 Movie Roulette Tuesday"), ("12 Angry Men", "12 Angry Men Movie Roulette Tuesday"),
    ("2001: A Space Odyssey", "2001 A Space Odyssey Movie Roulette Tuesday"), ("E.T. the Extra-Terrestrial", "E T the Extra-Terrestrial Movie Roulette Tuesday"),
    ("Episode 12", "Movie Roulette Tuesday"), ("Buzzsprout-19913482", "Movie Roulette Tuesday"), ("", "Movie Roulette Tuesday")]
let spotifyURLAndroid: [(String, String)] = [("Romeo + Juliet", "Romeo%20Juliet%20Movie%20Roulette%20Tuesday"), ("Palmer Rockey's SCARLET WARNING 666", "Palmer%20Rockey%27s%20SCARLET%20WARNING%20666%20Movie%20Roulette%20Tuesday"),
    ("Kon-Tiki", "Kon-Tiki%20Movie%20Roulette%20Tuesday"), ("π", "%CF%80%20Movie%20Roulette%20Tuesday")]
let artAndroid: [(String, String?)] = [(" https://a.example/x.jpg ", "https://a.example/x.jpg"), ("http://a.example/x.jpg", "https://a.example/x.jpg"), ("file:///etc/passwd", nil),
    ("javascript:alert(1)", nil), ("/relative.jpg", nil), ("", nil)]
let bzAndroid: [(String, String?)] = [("Buzzsprout-19913482", "https://www.buzzsprout.com/2117292/episodes/19913482"), ("https://example.com/ep", nil), ("Buzzsprout-abc", nil)]
let rssAndroid: J = [
    "description": "Cases copied from Android main unit tests (inputs + Android's asserted value) and re-run on iOS RouletteCore. `expected` is the iOS value and is authoritative; `agrees` false = see DISCREPANCIES.md.",
    "spotifySearchQuery": spotifyAndroid.map { xc("PodcastLinksTest.spotifyQuery*", $0.0, $0.1, PodcastLinks.spotifySearchQuery(episodeTitle: $0.0)) },
    "spotifySearchURL": spotifyURLAndroid.map { xc("PodcastLinksTest.spotifySearchUrlEncodedOnce", $0.0, "https://open.spotify.com/search/" + $0.1, PodcastLinks.spotifySearch(episodeTitle: $0.0)?.absoluteString) },
    "artworkUsableURL": artAndroid.map { xc("EpisodeModelsTest.artworkResolver", $0.0, $0.1, ArtworkResolver.usableURL($0.0)?.absoluteString) },
    "buzzsproutEpisode": bzAndroid.map { xc("PodcastLinksTest.showAndEpisodeLinks", $0.0, $0.1, PodcastLinks.buzzsproutEpisode(guid: $0.0)?.absoluteString) },
    "parseDate": [("Tue, 06 Oct 2026 00:00:00 -0400", "2026-10-06T04:00:00Z"), ("06 Oct 2026 04:00:00 GMT", "2026-10-06T04:00:00Z"), (" Tue, 06 Oct 2026 04:00 +0000 ", "2026-10-06T04:00:00Z"),
                  ("Tue, 06 Oct 2026 00:00:00 EDT", "2026-10-06T04:00:00Z"), ("", nil), ("yesterday", nil)].map { (i: String, a: String?) in xc("RssFeedParserTest.dateVariants", i, a, date(RSSFeedParser.parseDate(i))) },
    "stripFanMail": [("Send us Fan Mail Hi there", "Hi there"), ("send us fanmail: Hi", "Hi"), ("We read fan mail today", "We read fan mail today"), ("Send us Fan Mail", "")].map { xc("RssFeedParserTest.showNotesHelpers", $0.0, $0.1, ShowNotes.strippingFanMail($0.0)) },
    "fanMailURL": [("<p>No link</p>", nil), (##"<a href="https://example.com/x">Other</a>"##, nil),
                   (##"<p><a target="_blank" href="https://www.buzzsprout.com/1/fan_mail/new">Send us Fan Mail</a></p>"##, "https://www.buzzsprout.com/1/fan_mail/new"),
                   (##"<a href="javascript:alert(1)">fan mail</a>"##, nil)].map { (i: String, a: String?) in xc("RssFeedParserTest.showNotesHelpers", i, a, ShowNotes.fanMailURL(inHTML: i)?.absoluteString) },
]
// "Discussed on" formats (SPEC §2.3 / E10) + the shared collapse rule (Q9).
let dFeed: [String: PodcastEpisode] = PodcastEpisode.byGUID([
    PodcastEpisode(guid: "g1", title: "The Outsiders", season: 4, episode: 34),
    PodcastEpisode(guid: "g2", title: "Laura", season: 4, episode: 35),
    PodcastEpisode(guid: "g3", title: "Bonus Chat"),
    PodcastEpisode(guid: "g4", title: "Mailbag", season: 2, episode: 1)])
func sharedDiscussed(_ m: Movie, _ feed: [String: PodcastEpisode]) -> String {
    // Shared rule = iOS format, plus: identical labels collapse; the 1 / 2 / 3+ format uses DISTINCT labels.
    let ids = m.episodeIds
    if ids.isEmpty { return "Not discussed on the show yet" }
    if ids.allSatisfy({ EpisodeLabel.sampleEpisodeNumber(from: $0) != nil }) { return EpisodeLabel.discussedText(for: m, episodesByGUID: feed) }
    var labels: [String] = []
    for id in ids {
        let t = EpisodeLabel.title(forEpisodeId: id, movie: m, episodesByGUID: feed)
        let l = feed[id]?.seasonEpisodeLabel.map { "\(t) (\($0))" } ?? t
        if !labels.contains(l) { labels.append(l) }
    }
    switch labels.count {
    case 1: return "Discussed on \(labels[0])"
    case 2: return "Discussed on \(labels[0]) & \(labels[1])"
    default: return "Discussed on \(labels[0]) + \(labels.count - 1) more"
    }
}
let dCases: [(String, [String], String?, Bool)] = [
    ("no ids", [], nil, true), ("1 id in feed with S/E", ["g1"], nil, true), ("1 id in feed without S/E", ["g3"], nil, true),
    ("1 id, no feed, episodeTitle", ["g1"], "Ep Title", false), ("1 id not in feed, no episodeTitle -> raw guid", ["Buzzsprout-123"], nil, true),
    ("2 ids in feed", ["g1", "g2"], nil, true), ("3 ids in feed", ["g1", "g2", "g4"], nil, true), ("4 ids, one missing (episodeTitle used)", ["g1", "x9", "g2", "g4"], "Ep Title", true),
    ("2 ids, no feed -> identical labels (Q9)", ["g1", "g2"], "Ep Title", false), ("3 ids, no feed -> identical labels (Q9)", ["g1", "g2", "g4"], "Ep Title", false),
    ("3 ids, 2 distinct labels", ["g1", "zz", "yy"], "Ep Title", true),
    ("2 ids, one in feed one via episodeTitle", ["g1", "zz"], "Ep Title", true),
    ("samples 1", ["sample-ep-6"], nil, true), ("samples 2", ["sample-ep-6", "sample-ep-7"], nil, true), ("samples 3", ["sample-ep-6", "sample-ep-7", "sample-ep-9"], nil, true)]
let discussedFormats: J = [
    "description": "EpisodeLabel.discussedText (SPEC §2.3). Formats: 0 ids -> 'Not discussed on the show yet'; label = title + ' (S4E34)' when the feed has S/E; 1 -> 'Discussed on A'; 2 -> 'Discussed on A & B'; 3+ -> 'Discussed on A + N more'. Title source: feed title, else movie.episodeTitle, else 'Episode n' for sample ids, else the raw guid. `iosB673df1` = what iOS main renders today; `expected` = shared rule decided by MRT App: identical labels collapse and the 1/2/3+ format uses the DISTINCT label count (Q9; iOS fix is a 1.0.1 candidate). Siri always renders with no feed.",
    "feed": dFeed.values.sorted { $0.guid < $1.guid }.map { ["guid": $0.guid, "title": $0.title, "season": opt($0.season), "episode": opt($0.episode)] as J },
    "cases": dCases.map { (name, ids, epTitle, withFeed) -> J in
        let m = Movie(id: "m", title: "M", year: 2000, genre: "Drama", episodeIds: ids, episodeTitle: epTitle)
        let f = withFeed ? dFeed : [:]
        let ios = EpisodeLabel.discussedText(for: m, episodesByGUID: f), shared = sharedDiscussed(m, f)
        return ["name": name, "episodeIds": ids, "episodeTitle": opt(epTitle), "feedLoaded": withFeed, "iosB673df1": ios, "expected": shared, "iosMatchesSharedRule": ios == shared]
    }]
let feedURLRule: J = [
    "description": "SPEC §2.1 / E5: the feed URL is hard-coded. show.rssURL from the catalog is decoded but NEVER used to fetch (Episodes tab and background alert check).",
    "source": "RouletteCore/EpisodeStoreCore.swift:8; Episodes/EpisodeStore.swift:33; MovieRouletteTuesdayApp.swift:7,18; Shared/NewEpisodeAlerts.swift:87",
    "cases": [["catalogShowRssURL": NSNull(), "fetchURL": EpisodeFeedIO.defaultFeedURL.absoluteString] as J,
              ["catalogShowRssURL": "https://rss.buzzsprout.com/2117292.rss", "fetchURL": EpisodeFeedIO.defaultFeedURL.absoluteString],
              ["catalogShowRssURL": "https://example.com/other.rss", "fetchURL": EpisodeFeedIO.defaultFeedURL.absoluteString]],
    "httpCaching": ["feedRequest": "useProtocolCachePolicy (HTTP caching applies)", "catalogRequest": "bypasses the HTTP cache"] as J]
let refreshRule: J = [
    "description": "Shared rule (MRT App, Q2): the PARSER may return 0 episodes; the REFRESH treats 0 episodes (or a parse error) as a failure: cache file untouched, current list kept, soft error shown. iOS b673df1 instead saves and applies the empty feed (bug, 1.0.1 candidate); Android follows the shared rule.",
    "cases": [["feed": "empty-channel (see feeds[])", "parse": ["ok": true, "episodes": 0] as J, "expected": ["refresh": "failed", "cacheOverwritten": false, "episodesListChanged": false] as J, "iosB673df1": ["refresh": "succeeded", "cacheOverwritten": true, "episodesListChanged": true] as J] as J,
              ["feed": "not-xml / truncated rss (see feeds[])", "parse": "ok with 0 episodes, or malformed (platform-dependent)", "expected": ["refresh": "failed", "cacheOverwritten": false, "episodesListChanged": false] as J, "iosB673df1": "Linux probe: succeeded with 0 episodes, cache overwritten; Darwin unverified"],
              ["feed": "buzzsprout-fixture", "parse": ["ok": true, "episodes": 2] as J, "expected": ["refresh": "succeeded", "cacheOverwritten": true, "episodesListChanged": true] as J, "iosB673df1": ["refresh": "succeeded", "cacheOverwritten": true, "episodesListChanged": true] as J]]]
write("rss.json", [
    "description": "Buzzsprout RSS parsing (SPEC §2). feeds[].input is the raw XML; expected.episodes is the parsed list in feed order after guid de-duplication. pubDate is ISO-8601 UTC. summary = longest of (description, content:encoded, itunes:summary) after HTML strip + fan-mail strip.",
    "feedURL": EpisodeFeedIO.defaultFeedURL.absoluteString,
    "androidCrossCheck": rssAndroid, "feedURLRule": feedURLRule, "refreshRule": refreshRule, "discussedFormats": discussedFormats, "feeds": feeds, "parseDate": dateCases, "stripFanMail": fanStrip, "fanMailURL": fanURL,
    "matching": ["description": "Episode -> movie: first catalog movie whose episodeIds contains the guid (exact, case-sensitive).", "catalog": catJSON(matchCatalog),
                 "feedGuids": feedForMatch.map(\.guid), "cases": matchCases, "discussedText": discussed,
                 "episodeTotals": ["feedEpisodes": totals.feedEpisodes, "feedEpisodesWithFilm": totals.feedEpisodesWithFilm, "catalogEpisodeCount": EpisodeTotals.catalogEpisodeCount(matchCatalog)]],
    "links": ["spotifySearch": spotify,
              "appleSearch": ["The Outsiders", "Romeo + Juliet"].map { ["episodeTitle": $0, "url": opt(PodcastLinks.appleSearch(episodeTitle: $0)?.absoluteString)] as J },
              "buzzsproutEpisode": ["Buzzsprout-19913482", "Buzzsprout-x", "other-1"].map { ["guid": $0, "url": opt(PodcastLinks.buzzsproutEpisode(guid: $0)?.absoluteString)] as J }],
])

// MARK: 3. Randomness + selection
func rngCase(_ seed: UInt64) -> J {
    var a = SeededRandomNumberGenerator(seed: seed); let raw = (0..<4).map { _ in String(format: "%016llx", a.next()) }
    var b = SeededRandomNumberGenerator(seed: seed); let units = (0..<4).map { _ in Double.random(in: 0..<1, using: &b) }
    var c = SeededRandomNumberGenerator(seed: seed); let turns = (0..<4).map { _ in Int.random(in: 5...8, using: &c) }
    var d = SeededRandomNumberGenerator(seed: seed); let idx3 = (0..<4).map { _ in Int.random(in: 0..<3, using: &d) }
    var e = SeededRandomNumberGenerator(seed: seed); let deg = (0..<4).map { _ in Double.random(in: 0..<360, using: &e) }
    return ["seed": seed, "nextUInt64Hex": raw, "unitDoubles": units, "intIn5through8": turns, "intIn0until3": idx3, "doubleIn0until360": deg]
}
let sel = MovieSelector()
let catA = fixtureCatalog.category(withId: "a")!
func h(_ ids: [String], cat: String = "x") -> [SpinResult] { ids.map { SpinResult(movieId: $0, categoryId: cat, timestamp: Date(timeIntervalSince1970: 0)) } }
let recency: [J] = [nil, 0, 1, 2, 3, 4, 5, 6, 100].map { (n: Int?) in ["spinsAgo": opt(n), "expected": sel.recencyMultiplier(spinsAgo: n)] }
let weightHistories: [(String, [String])] = [("none", []), ("a-1 last", ["a-1"]), ("a-1 two ago", ["a-1", "b-1"]), ("a-1 five ago", ["a-1", "x", "x", "x", "x"]), ("a-1 six ago", ["a-1", "x", "x", "x", "x", "x"]), ("both recent", ["a-2", "a-1"]), ("a-1 twice, most recent counts", ["a-1", "x", "a-1", "x"])]
let weightCases: [J] = weightHistories.flatMap { name, ids -> [J] in
    [fixtureCatalog, infamousCatalog].map { cat -> J in
        let w = sel.weightedCandidates(for: cat.category(withId: "a")!, in: cat, history: h(ids))
        let catB = cat.category(withId: "b")!
        let wb = sel.weightedCandidates(for: catB, in: cat, history: h(ids))
        let tot = w.map(\.weight).reduce(0, +), totb = wb.map(\.weight).reduce(0, +)
        return ["name": name, "catalog": cat == fixtureCatalog ? "fixture" : "fixtureInfamous", "historyMovieIds": ids,
                "category_a": w.map { ["movieId": $0.movie.id, "weight": $0.weight, "probability": $0.weight / tot] as J },
                "category_b": wb.map { ["movieId": $0.movie.id, "weight": $0.weight, "probability": $0.weight / totb] as J }]
    }
}
let pickCases: [([Double], Double, String)] = [([1, 2, 1], 0, "android"), ([1, 2, 1], 0.2499, "android"), ([1, 2, 1], 0.25, "android"), ([1, 2, 1], 0.75, "android"), ([1, 2, 1], 1.0, "android"), ([], 0.5, "android"), ([0, 1, -1, .nan], 0.99, "android"), ([0, 0, 0], 0.9, "android"), ([1, 1], .nan, "android"), ([1, 1], -5, "ios"), ([1, 1], 0.5, "ios"), ([0.1, 1, 1], 0.0476, "ios"), ([.infinity, 1], 0.1, "ios"), ([1, 0, 0], 0.999, "ios")]
let pick: [J] = pickCases.map { w, u, src in ["weights": w.map(num), "unitValue": num(u), "expected": opt(MovieSelector.pickIndex(weights: w, unitValue: u)), "source": src == "android" ? "android-main:MovieSelectorTest.pickIndexExactIntervalsAndEdgeCases" : "ios"] }
let candidatesCase: J = {
    var c = fixtureCatalog; var extra = c.movies[0]; extra = Movie(id: "tagged", title: extra.title, year: extra.year, genre: extra.genre, categories: ["a"]); c.movies.append(extra)
    var cat = c.category(withId: "a")!; cat.movieIds = ["a-1", "a-1", "ghost"]
    return ["source": "android-main:MovieSelectorTest.candidatesUnionCategoryListAndMovieTagsWithoutDuplicates", "categoryMovieIds": cat.movieIds, "extraMovie": ["id": "tagged", "categories": ["a"]], "expected": sel.candidates(for: cat, in: c).map(\.id)]
}()
func seededPicks(_ seed: UInt64, _ cat: MovieCatalog, _ catId: String, _ hist: [String], n: Int) -> J {
    var rng = SeededRandomNumberGenerator(seed: seed)
    let picks = (0..<n).map { _ in sel.selectMovie(from: cat.category(withId: catId)!, in: cat, history: h(hist), using: &rng)?.id ?? "nil" }
    return ["seed": seed, "catalog": cat == fixtureCatalog ? "fixture" : (cat == infamousCatalog ? "fixtureInfamous" : "bundled"), "categoryId": catId, "historyMovieIds": hist, "picks": picks, "note": "history is fixed (not appended) between picks; one unit double consumed per pick"]
}
let horrorHist = Array(MovieSelector().candidates(for: bundled.category(withId: "cat-horror")!, in: bundled).prefix(3).map(\.id))
let seeded: [J] = [seededPicks(1, fixtureCatalog, "a", [], n: 12), seededPicks(3, fixtureCatalog, "a", ["a-1"], n: 12), seededPicks(42, infamousCatalog, "b", ["b-2"], n: 12), seededPicks(2026, bundled, "cat-horror", horrorHist, n: 12), seededPicks(7, bundled, "cat-listener", [], n: 12)]
let bundledHorrorProb: J = {
    let w = sel.weightedCandidates(for: bundled.category(withId: "cat-horror")!, in: bundled, history: h(horrorHist.reversed() + ["x", "x"]))
    let t = w.map(\.weight).reduce(0, +)
    return ["catalog": "bundled", "categoryId": "cat-horror", "historyMovieIds": horrorHist.reversed() + ["x", "x"], "weights": w.filter { $0.weight != 1 }.map { ["movieId": $0.movie.id, "weight": $0.weight, "probability": $0.weight / t] as J }, "otherWeight": 1.0, "otherProbability": 1 / t, "candidateCount": w.count]
}()
// Rare outcomes
let rarePolicy = RareOutcomePolicy()
let rareUnits: [(Double, Bool, Bool, String)] = [(0, true, true, "android"), (0.0099, true, true, "android"), (0.01, true, true, "android"), (0.0199, true, true, "android"), (0.02, true, true, "android"), (0.015, false, true, "android"), (0.005, true, false, "android"), (.nan, true, true, "android"), (-1, true, true, "ios"), (0.5, true, true, "ios"), (0.999, true, true, "ios")]
let rare: [J] = rareUnits.map { u, inf, allow, src in ["unitValue": num(u), "infamousAvailable": inf, "allowRespin": allow, "expected": RareOutcomeRoller.outcome(unitValue: u, policy: rarePolicy, infamousAvailable: inf, allowRespin: allow).rawValue, "source": src == "android" ? "android-main:RareOutcomeTest" : "ios"] }
    + [["unitValue": 0.0, "policy": "disabled", "infamousAvailable": true, "allowRespin": true, "expected": RareOutcomeRoller.outcome(unitValue: 0, policy: .disabled, infamousAvailable: true).rawValue, "source": "android-main:RareOutcomeTest.disabledAndBadInput"]]
let clampCases: [J] = [(0.8, 0.8), (-1, 2), (Double.nan, 0.5), (0.01, 0.01)].map { r, j in let p = RareOutcomePolicy(forcedRespinChance: r, infamousJackpotChance: j); return ["forcedRespinChance": num(r), "infamousJackpotChance": num(j), "effective": ["forcedRespin": p.forcedRespinChance, "infamousJackpot": p.infamousJackpotChance]] }
func jackpotCase(_ seed: UInt64, landed: String) -> J {
    var rng = SeededRandomNumberGenerator(seed: seed)
    let p = RareOutcomeRoller.jackpotPick(in: infamousCatalog, landed: infamousCatalog.category(withId: landed)!, listenerAverages: fixtureListenerAverages, using: &rng)
    return ["seed": seed, "catalog": "fixtureInfamous", "landed": landed, "movieId": opt(p?.movie.id), "categoryId": opt(p?.category.id)]
}
let jackpots: [J] = [jackpotCase(1, landed: "a"), jackpotCase(2, landed: "a"), jackpotCase(3, landed: "d"), jackpotCase(4, landed: "b"), jackpotCase(5, landed: "c")]
// QuickSpin end-to-end
func quick(_ seed: UInt64, _ c: MovieCatalog, _ name: String) -> J {
    var rng = SeededRandomNumberGenerator(seed: seed)
    let o = QuickSpin.resolve(catalog: c, history: [], rareOutcomes: .default, using: &rng)
    return ["seed": seed, "catalog": name, "landed": opt(o?.landed.id), "categoryId": opt(o?.category.id), "movieId": opt(o?.movie.id), "isJackpot": opt(o?.isJackpot), "wasForcedRespin": opt(o?.wasForcedRespin)]
}
var quickCases: [J] = (1...8).map { quick(UInt64($0), bundled, "bundled") } + (1...8).map { quick(UInt64($0), infamousCatalog, "fixtureInfamous") }
// find seeds hitting forced respin / jackpot for coverage
var found = 0
for s in 100...5000 where found < 4 {
    var rng = SeededRandomNumberGenerator(seed: UInt64(s))
    if let o = QuickSpin.resolve(catalog: infamousCatalog, history: [], rareOutcomes: .default, using: &rng), o.isJackpot || o.wasForcedRespin { quickCases.append(quick(UInt64(s), infamousCatalog, "fixtureInfamous")); found += 1 }
}
// App spin sequence (RouletteViewModel order)
func appSequence(seed: UInt64, catalog c: MovieCatalog, name: String, spins: Int, reduceMotion: Bool) -> J {
    var rng = SeededRandomNumberGenerator(seed: seed)
    let g = WheelGeometry(categories: c.categories)
    var rotation = 0.0, history: [SpinResult] = [], out: [J] = [], forced = false, attempts = 0
    while out.count < spins && attempts < spins * 3 {
        attempts += 1
        let target = g.randomTargetRotation(from: rotation, fullTurns: reduceMotion ? 1...2 : 5...8, using: &rng)
        rotation = target
        let landed = c.categories[g.segmentIndex(forRotation: rotation)]
        let o = RareOutcomeRoller.roll(policy: RareOutcomePolicy(isEnabled: true), infamousAvailable: !RareOutcomeRoller.jackpotCandidates(in: c).isEmpty, allowRespin: !forced, using: &rng)
        if o == .forcedRespin { out.append(["rotation": rotation, "landed": landed.id, "outcome": "forcedRespin"]); forced = true; continue }
        var movie: Movie, cat = landed, jack = false
        if o == .infamousJackpot, let p = RareOutcomeRoller.jackpotPick(in: c, landed: landed, listenerAverages: fixtureListenerAverages, using: &rng) { movie = p.movie; cat = p.category; jack = true }
        else { movie = sel.selectMovie(from: landed, in: c, history: history, using: &rng)! }
        history.append(SpinResult(movieId: movie.id, categoryId: cat.id))
        out.append(["rotation": rotation, "landed": landed.id, "outcome": jack ? "infamousJackpot" : "normal", "movieId": movie.id, "categoryId": cat.id, "wasForcedRespin": forced])
        forced = false
    }
    return ["seed": seed, "catalog": name, "reduceMotion": reduceMotion, "startRotation": 0, "steps": out]
}
let richSequence: J = {
    for seed in UInt64(1)...UInt64(2000) {
        let j = appSequence(seed: seed, catalog: infamousCatalog, name: "fixtureInfamous", spins: 60, reduceMotion: false)
        let outs = (j["steps"] as! [J]).map { $0["outcome"] as! String }
        if outs.contains("forcedRespin") && outs.contains("infamousJackpot") { return j }
    }
    fatalError("no rich seed")
}()
write("selection.json", [
    "description": "Randomness, movie selection, rare outcomes, full spins (SPEC §3.3-3.5). Seeded cases use SplitMix64 (SPEC §4.1) AND the iOS mapping from 64-bit outputs to doubles/ints; an Android port must implement that mapping (see DISCREPANCIES.md D1) to reproduce seeded cases.",
    "fixtures": ["fixture": catJSON(fixtureCatalog), "fixtureInfamous": catJSON(infamousCatalog), "bundled": "the bundled movies.json at the iOS commit in _generated (sha256 in catalog.json bundled.sha256)"],
    "rng": [rngCase(0), rngCase(1), rngCase(42), rngCase(2026), rngCase(0xFFFF_FFFF_FFFF_FFFF)],
    "recencyMultiplier": recency, "weights": weightCases, "bundledHorrorWeights": bundledHorrorProb, "pickIndex": pick, "candidates": candidatesCase,
    "seededSelectMovie": seeded,
    "rareOutcome": ["policy": ["forcedRespinChance": rarePolicy.forcedRespinChance, "infamousJackpotChance": rarePolicy.infamousJackpotChance], "cases": rare, "policyClamping": clampCases, "jackpotPick": jackpots],
    "quickSpin": ["description": "QuickSpin.resolve(catalog, history: [], default policy) (Siri/Shortcuts path): per attempt randomTargetRotation(from: 0, fullTurns: 1...1) (NOTE E11: Int.random(in: 1...1) still consumes one next(), so each attempt uses 2 draws for the target) then roll, then jackpotPick or selectMovie.", "cases": quickCases],
    "appSpinSequence": ["description": "RouletteViewModel order per spin: randomTargetRotation(from: current rotation, 5...8 or 1...2 with reduce motion) -> landed = segmentIndex -> roll(allowRespin: !lastWasForced) -> forced: next step is the automatic re-spin; jackpot: jackpotPick; else selectMovie(history so far). History accumulates.",
                        "cases": [appSequence(seed: 2026, catalog: bundled, name: "bundled", spins: 25, reduceMotion: false), appSequence(seed: 7, catalog: bundled, name: "bundled", spins: 10, reduceMotion: true), richSequence]],
])

// MARK: 4. Wheel
let pointer: [J] = [0, 1, 36, 36.5, -36, 324, 360, 720.25, -1e9, -0.0, 1e-12, 1e12, 12.3 + 360 * 1000, .nan, .infinity].map { ["rotation": num($0), "pointerAngle": WheelMath.pointerAngle(forRotation: $0), "segmentIndex10": WheelMath.segmentIndex(forRotation: $0, segmentCount: 10), "segmentIndex7": WheelMath.segmentIndex(forRotation: $0, segmentCount: 7)] }
func geo(_ w: [Double?], _ name: String, probes: [Double]) -> J {
    let g = WheelGeometry(weights: w)
    return ["name": name, "weights": w.map { $0.map(num) ?? NSNull() }, "isUniform": g.isUniform,
            "segments": g.segments.map { ["index": $0.index, "start": $0.startAngle, "end": $0.endAngle, "mid": $0.midAngle] as J },
            "probes": probes.map { ["rotation": num($0), "pointerAngle": WheelMath.pointerAngle(forRotation: $0), "segmentIndex": g.segmentIndex(forRotation: $0)] as J }]
}
let probes: [Double] = [0, -0.0001, -89.9999, -90, -100, -270, -359.999, 10, 90, 180, 3600 + 45]
let geometries: [J] = [geo(Array(repeating: 1, count: 10), "uniform-10 (bundled wheel)", probes: probes + [-36, -35.999, 1, 36, 36.5]), geo([1, 2, 1], "weighted-1-2-1", probes: probes), geo([nil, -1, .nan, 0], "invalid-weights-count-as-1", probes: probes), geo([], "empty-is-one-segment", probes: [0, 123]), geo([3, 1], "weighted-3-1", probes: probes), geo([1], "single", probes: [0, 77])]
func target(_ seed: UInt64, _ w: [Double?], from: Double, turns: ClosedRange<Int>) -> J {
    var rng = SeededRandomNumberGenerator(seed: seed); let g = WheelGeometry(weights: w)
    let t = g.randomTargetRotation(from: from, fullTurns: turns, using: &rng)
    return ["seed": seed, "weights": w.map { $0.map(num) ?? NSNull() }, "from": from, "fullTurns": [turns.lowerBound, turns.upperBound], "edgePadding": 3, "target": t, "segmentIndex": g.segmentIndex(forRotation: t), "pointerAngle": WheelMath.pointerAngle(forRotation: t)]
}
let targets: [J] = (0..<6).map { target(UInt64($0), Array(repeating: 1, count: 10), from: 0, turns: 5...8) } + [target(42, [1, 2, 1], from: 1234.5, turns: 5...8), target(9, Array(repeating: 1, count: 10), from: 0, turns: 1...2), target(11, Array(repeating: 1, count: 40), from: 0, turns: 5...8), target(13, Array(repeating: 1, count: 200), from: 0, turns: 0...0)]
let gu = WheelGeometry(segmentCount: 4)
let boundaries: [J] = [["from": 0, "to": 720, "segmentCount": 4, "expected": SpinTicks.boundaryRotations(from: 0, to: 720, geometry: gu)], ["from": 10, "to": 100, "segmentCount": 4, "expected": SpinTicks.boundaryRotations(from: 10, to: 100, geometry: gu)], ["from": 0, "to": 360, "segmentCount": 1, "expected": SpinTicks.boundaryRotations(from: 0, to: 360, geometry: WheelGeometry(segmentCount: 1))]]
let curve = TimingCurve.spin
let timing: [J] = [0, 0.1, 0.25, 0.5, 0.75, 0.9, 1].map { ["t": $0, "spinCurveProgress": curve.progress(atTimeFraction: $0), "easeOutProgress": TimingCurve.easeOut.progress(atTimeFraction: $0), "spinCurveTimeAtProgress": curve.timeFraction(atProgress: $0)] }
let base: [J] = [0, 0.1, 0.45, 1, 2, 3, 4, 5, 6, 6.204, 6.25, 6.294, 7].map { ["t": $0, "baseProgress": SpinMotion.baseProgress(at: $0)] }
let baseInv: [J] = [0, 0.01, 0.1, 0.5, 0.9, 0.99, 1].map { ["p": $0, "baseTime": SpinMotion.baseTime(atProgress: $0)] }
let g10 = WheelGeometry(segmentCount: 10)
var mrng = SeededRandomNumberGenerator(seed: 2026)
let mTarget = g10.randomTargetRotation(from: 0, fullTurns: 5...8, using: &mrng)
let plan = SpinMotion.plan(from: 0, to: mTarget, geometry: g10)
let motion: J = ["from": 0, "to": mTarget, "segmentCount": 10, "duration": plan.duration, "crossingCount": plan.crossingTimes.count, "crossingTimes": plan.crossingTimes,
                 "snapOffsets": plan.snapOffsets, "snappedCount": plan.snapOffsets.filter { $0 != 0 }.count,
                 "progressSamples": [0.0, 0.5, 1, 2, 3, 4, 5, 6, 6.2, 6.29, 6.3].map { ["t": $0, "progress": plan.progress(at: $0)] as J },
                 "note": "Full click-locked plan (SpinMotion.plan). Android main implements only the base curve (DISCREPANCIES.md D4)."]
var srng = SeededRandomNumberGenerator(seed: 5)
let stop = SpinStopPlan.make(motion: plan, start: 0, oldTarget: mTarget, elapsed: 2.0, geometry: g10, using: &srng)
var cr = CountingRNG(seed: 5)
let stopCounted = SpinStopPlan.make(motion: plan, start: 0, oldTarget: mTarget, elapsed: 2.0, geometry: g10, using: &cr)
var manual = SeededRandomNumberGenerator(seed: 5); _ = manual.next(); let secondUnit = Double.random(in: 0..<360, using: &manual)
let stopDraws: J = ["rngDrawsConsumed": cr.draws, "sameResultAsUncounted": stopCounted?.newTarget == stop?.newTarget,
    "explanation": "SpinStopPlan.randomTarget = randomTargetRotation(from: current+120, fullTurns: 0...0). Int.random(in: 0...0) still consumes ONE next() (Lemire, n=1), then ONE next() for the extra angle: 2 draws total. secondDrawExtraDegrees = draw 2 of seed 5 as Double in [0,360), before edge padding.",
    "secondDrawExtraDegrees": secondUnit]
let stopJ: J = ["drawAccounting": stopDraws, "seed": 5, "elapsed": 2.0, "start": 0, "oldTarget": mTarget, "currentAngle": opt(stop?.currentAngle), "newTarget": opt(stop?.newTarget), "landedIndex": opt(stop.map { g10.segmentIndex(forRotation: $0.newTarget) }),
                "displayedAngleAtEnd": opt(stop?.displayedAngle(at: 2.8)), "tooLateReturnsNil": SpinStopPlan.make(motion: plan, start: 0, oldTarget: mTarget, elapsed: plan.duration - 0.5, geometry: g10, using: &srng) == nil]
let layouts: [J] = [(393.0, 700.0, false, 40.0), (1024, 1366, true, 40), (1366, 1024, true, 40), (1920, 1080, true, 0), (320, 480, false, 40), (690, 700, true, 40)].map { w, hgt, reg, hint in
    let l = RouletteLayout.make(width: w, height: hgt, isRegularWidth: reg)
    let slotW = l.arrangement == .sideBySide ? w - RouletteLayout.sideBySideControlsWidth(forWidth: w) : w
    let d = RouletteLayout.wheelDiameter(slotWidth: slotW, slotHeight: hgt, arrangement: l.arrangement, isRegularWidth: reg, hintHeight: hint)
    return ["width": w, "height": hgt, "isRegularWidth": reg, "hintHeight": hint, "arrangement": l.arrangement == .sideBySide ? "sideBySide" : "stacked",
            "slotWidthUsed": slotW, "wheelDiameter": d, "pointerSize": [RouletteLayout.pointerSize(forDiameter: d).width, RouletteLayout.pointerSize(forDiameter: d).height],
            "controlsWidth": RouletteLayout.sideBySideControlsWidth(forWidth: w)]
}
let statsCols: [J] = [(500.0, false), (500, true), (640, true), (1099, true), (1100, true)].map { ["width": $0.0, "isRegularWidth": $0.1, "columns": StatsGridLayout.columnCount(forWidth: $0.0, isRegularWidth: $0.1)] }
let links: [J] = ["mrt://movie/the-outsiders-1983", "mrt:///movie/abc", "MRT://Movie/X", "mrt://episode/Buzzsprout-19913482", "mrt://movie/a%2Fb", "mrt://movie/", "mrt://other/x", "https://movie/x", "mrt://movie/a/b"].map { s in
    let l = URL(string: s).flatMap(DeepLink.init(url:))
    var r: J = ["url": s, "kind": NSNull(), "id": NSNull(), "roundTrip": NSNull()]
    if let l { switch l { case .movie(let id): r["kind"] = "movie"; r["id"] = id; case .episode(let g): r["kind"] = "episode"; r["id"] = g; default: break }; r["roundTrip"] = l.url.absoluteString }
    return r
}
write("wheel.json", [
    "description": "Wheel geometry, slice mapping, spin targets, motion timing, layout (SPEC §3.1-3.2, §3.5, §8 deep links, §11). Angles in degrees, clockwise from 12 o'clock; positive rotation = clockwise; pointer fixed at 12 o'clock.",
    "pointer": pointer, "geometries": geometries, "randomTargets": targets, "boundaryRotations": boundaries,
    "timingCurves": ["spin": [curve.c1x, curve.c1y, curve.c2x, curve.c2y], "easeOut": [0, 0, 0.58, 1], "samples": timing],
    "spinMotion": ["spinDuration": SpinSoundTrack.spinDuration, "baseProgress": base, "baseTimeAtProgress": baseInv, "plan": motion, "stopPlan": stopJ],
    "layout": ["roulette": layouts, "statsColumns": statsCols, "confetti": [430.0, 1024, 200].map { ["width": $0, "particles": ConfettiScale.particleCount(forWidth: $0), "pieceScale": ConfettiScale.pieceScale(forWidth: $0)] as J }],
    "deepLinks": links,
])

// MARK: 5. Stats + local logic
let t0 = parseISO("2026-10-01T12:00:00Z")
func sr(_ m: String, _ c: String, _ i: Int) -> SpinResult { SpinResult(movieId: m, categoryId: c, timestamp: t0.addingTimeInterval(Double(i) * 3600)) }
let statHistory = [sr("a-1", "a", 0), sr("a-1", "a", 1), sr("b-1", "b", 2), sr("a-2", "a", 3), sr("a-1", "a", 4), sr("c-1", "c", 5), sr("ghost", "zzz", 6)]
let genreCatalog: MovieCatalog = { var c = fixtureCatalog; c.movies = c.movies.map { m in var m = m; m.genre = m.id.hasPrefix("a") ? "Horror" : (m.id.hasPrefix("b") ? "Comedy" : "Drama"); return m }; return c }()
/// Shared tie rule (MRT App, Q6): count descending, then id/genre ascending by plain code points.
/// iOS b673df1 leaves ties in per-process Dictionary order (bug, 1.0.1 candidate). `expected` applies the shared
/// rule to the counts iOS computed; the multiset of (key, count) is exactly iOS's.
func tieSorted(_ xs: [(String, Int)]) -> [(String, Int)] {
    xs.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.unicodeScalars.map(\.value).lexicographicallyPrecedes($1.0.unicodeScalars.map(\.value)) }
}
func movieHits(_ hist: [SpinResult], _ archive: SpinHistoryArchive) -> [(String, Int)] {
    var h = archive.movieCounts; for r in hist { h[r.movieId, default: 0] += 1 }; return h.map { ($0.key, $0.value) }
}
func snap(_ hist: [SpinResult], archive: SpinHistoryArchive, name: String) -> J {
    let s = StatsCalculator.snapshot(history: hist, catalog: genreCatalog, archive: archive, recentLimit: 3)
    return ["name": name, "history": hist.map(spinJSON), "archive": ["totalSpins": archive.totalSpins, "movieCounts": archive.movieCounts, "categoryCounts": archive.categoryCounts],
            "expected": ["totalSpins": s.totalSpins, "distinctMovies": s.distinctMovies, "mostSpunMovie": tieSorted(movieHits(hist, archive)).first.map { ["id": $0.0, "count": $0.1] as J } as Any? ?? NSNull(),
                         "mostSpunCategory": tieSorted(s.categoryBreakdown.map { ($0.id, $0.count) }).first.map { ["id": $0.0, "count": $0.1] as J } as Any? ?? NSNull(),
                         "categoryBreakdown": tieSorted(s.categoryBreakdown.map { ($0.id, $0.count) }).map { ["id": $0.0, "count": $0.1] as J }, "genreBreakdown": tieSorted(s.genreBreakdown.map { ($0.genre, $0.count) }).map { ["genre": $0.0, "count": $0.1] as J },
                         "recentMovieIds": s.recent.map(\.movieId)]]
}
let stats: [J] = [snap(statHistory, archive: .empty, name: "history-only"),
                  snap(statHistory, archive: SpinHistoryArchive(totalSpins: 7, movieCounts: ["d-1": 6, "a-2": 1], categoryCounts: ["d": 6, "a": 1]), name: "with-archive (archived movie counted in genre too)"),
                  snap([], archive: .empty, name: "empty"),
                  snap([sr("b-1", "b", 0), sr("a-1", "a", 1), sr("c-1", "c", 2), sr("a-2", "a", 3), sr("b-1", "b", 4)], archive: .empty, name: "ties (shared rule: count desc, then id asc; genre asc)")]
var log = SpinHistoryLog()
for i in 0..<5 { log.append(sr(i < 2 ? "old" : "m\(i)", "a", i), detailLimit: 3) }
let compaction: J = ["source": "android-main:SpinMotionAndHistoryTest.historyPersistsAndCompacts", "detailLimit": 3, "appendedMovieIds": ["old", "old", "m2", "m3", "m4"],
                     "expected": ["totalSpins": log.totalSpins, "detailedMovieIds": log.results.map(\.movieId), "archive": ["totalSpins": log.archive.totalSpins, "movieCounts": log.archive.movieCounts, "categoryCounts": log.archive.categoryCounts], "spinCountOld": log.stats.spinCount(forMovie: "old"), "defaultDetailLimit": SpinHistoryLog.defaultDetailLimit]]
let halfStars: J = [
    "clamped": [nil, -1, 0, 1, 10, 11].map { (v: Int?) in ["input": opt(v), "expected": opt(HalfStars.clamped(v))] as J },
    "roundedStars": (1...10).map { ["halfStars": $0, "expected": HalfStars.roundedStars($0)] as J },
    "resolved": [(nil, 4), (7, 4), (nil, nil), (0, 3), (nil, 9)].map { (a: Int?, b: Int?) in ["halfStars": opt(a), "legacyStars": opt(b), "expected": opt(HalfStars.resolved(halfStars: a, legacyStars: b))] as J },
    "roundedToHalf": [4.26, 4.25, 4.24, 3.75, 0.2, 5].map { ["stars": $0, "expected": HalfStars.roundedToHalf($0)] as J },
    "label": (1...10).map { ["halfStars": $0, "expected": HalfStars.label($0)] as J },
    "fromLocation": [(0.0, 100.0), (5, 100), (10, 100), (10.01, 100), (55, 100), (100, 100), (150, 100), (50, 0)].map { ["x": $0.0, "width": $0.1, "expected": HalfStars.fromLocation($0.0, width: $0.1)] as J },
    "adjusted": [(nil, true), (1, false), (2, false), (10, true), (5, true)].map { (h: Int?, inc: Bool) in ["halfStars": opt(h), "increment": inc, "expected": opt(HalfStars.adjusted(h, increment: inc))] as J },
]
let aggs: [J] = [[8, 9, 10, 3], [1], [], [0, 11, 7], [2, 4, 6, 8, 10]].map { v in let a = RatingAggregate.from(halfStars: v); return ["halfStars": v, "expected": ["count": a.count, "average": opt(a.average), "histogram": a.histogram, "averageToHalf": opt(a.averageToHalf), "averageHalfStars": opt(a.averageHalfStars)]] as J }
var pr = PersonalRatings()
pr.setHalfStars(9, for: "a-1"); pr.setHalfStars(9, for: "b-2"); pr.setHalfStars(4, for: "gone"); pr.setHalfStars(6, for: "c-1"); pr.setStatus(.wantToWatch, for: "d-1"); pr.setStatus(.watched, for: "a-1")
let prs = PersonalRatingsSummary(ratings: pr, catalog: fixtureCatalog, topLimit: 3)
let personal: J = ["input": ["halfStars": ["a-1": 9, "b-2": 9, "gone": 4, "c-1": 6], "status": ["d-1": "wantToWatch", "a-1": "watched"]], "catalog": "fixture (titles 'Movie a 1' etc.)",
                   "expected": ["ratedCount": prs.ratedCount, "averageStars": opt(prs.averageStars), "topRated": prs.topRated.map { ["movieId": $0.movieId, "title": $0.title, "halfStars": $0.halfStars] as J }, "watchlistCount": prs.watchlistCount, "watchedCount": prs.watchedCount]]
let polls: [J] = [["g", "good", "bad", "bad", "x"], ["yes"], []].map { votes in
    let p = PollFactory.defaultPoll(forEpisode: "Buzzsprout-19913482", hosts: ["Rachael", "Karl", "Matt"])
    let r = PollResults.tally(poll: PollDefinition(id: "p", episodeGuid: "g", question: "q", options: [PollOption(id: "good", label: "Good"), PollOption(id: "bad", label: "Bad")]), votes: votes)
    _ = p
    return ["options": ["good", "bad"], "votes": votes, "expected": ["total": r.total, "rows": r.rows.map { ["option": $0.option.id, "count": $0.count, "fraction": $0.fraction] as J }, "leaders": r.leaders.map(\.id)]]
}
let epDates = ["2026-10-06T04:00:00Z", "2026-09-29T04:00:00Z", "2026-09-22T04:00:00Z"]
let badgeEps = epDates.enumerated().map { PodcastEpisode(guid: "e\($0.offset)", title: "E\($0.offset)", pubDate: parseISO($0.element)) } + [PodcastEpisode(guid: "undated", title: "U")]
let badge: J = ["episodes": badgeEps.map { ["guid": $0.guid, "pubDate": date($0.pubDate)] as J },
                "count": [nil, "2026-09-30T00:00:00Z", "2026-10-06T04:00:00Z", "2026-01-01T00:00:00Z"].map { (lv: String?) in ["lastViewed": opt(lv), "expected": NewEpisodeBadge.count(episodes: badgeEps, lastViewed: lv.map(parseISO))] as J },
                "initialBaseline": date(NewEpisodeBadge.initialBaseline(episodes: badgeEps, now: t0)),
                "viewedTimestamp": [["now": "2026-10-01T12:00:00Z", "expected": date(NewEpisodeBadge.viewedTimestamp(episodes: badgeEps, now: t0))], ["now": "2026-10-10T00:00:00Z", "expected": date(NewEpisodeBadge.viewedTimestamp(episodes: badgeEps, now: parseISO("2026-10-10T00:00:00Z")))]]]
let oldFeed = Array(badgeEps.dropFirst())
let mark = NewEpisodeDiff.watermark(for: oldFeed)
let newOne = NewEpisodeDiff.newEpisodes(in: badgeEps, since: mark)
let two = [PodcastEpisode(guid: "n2", title: "Newer", pubDate: parseISO("2026-10-13T04:00:00Z"))] + badgeEps
let newTwo = NewEpisodeDiff.newEpisodes(in: two, since: mark)
let notify: J = ["description": "New-episode alert diff (SPEC §7).", "baselineFeedGuids": oldFeed.map(\.guid), "watermark": ["latestDate": date(mark.latestDate), "seenGUIDs": mark.seenGUIDs], "guidLimit": NewEpisodeWatermark.guidLimit,
                 "cases": [["feedGuids": badgeEps.map(\.guid), "new": newOne.map(\.guid), "text": NewEpisodeDiff.notificationText(for: newOne).map { ["title": $0.title, "body": $0.body] } ?? NSNull()],
                           ["feedGuids": two.map(\.guid), "new": newTwo.map(\.guid), "text": NewEpisodeDiff.notificationText(for: newTwo).map { ["title": $0.title, "body": $0.body] } ?? NSNull()],
                           ["feedGuids": badgeEps.map(\.guid), "watermark": NSNull(), "new": NewEpisodeDiff.newEpisodes(in: badgeEps, since: nil).map(\.guid), "text": NSNull()]]]
let groupEps = [PodcastEpisode(guid: "e5", title: "e5", pubDate: parseISO("2026-10-06T04:00:00Z"), season: 3), PodcastEpisode(guid: "b1", title: "b1", pubDate: parseISO("2026-06-01T04:00:00Z")), PodcastEpisode(guid: "e4", title: "e4", pubDate: parseISO("2026-01-02T04:00:00Z"), season: 3), PodcastEpisode(guid: "e3", title: "e3", pubDate: parseISO("2025-05-01T04:00:00Z"), season: 2), PodcastEpisode(guid: "e1", title: "e1", pubDate: parseISO("2024-02-01T04:00:00Z"), season: 1), PodcastEpisode(guid: "x", title: "x", season: nil)]
let grouping: J = ["calendarTimeZone": "UTC", "episodes": groupEps.map { ["guid": $0.guid, "pubDate": date($0.pubDate), "season": opt($0.season)] as J },
                   "season": EpisodeGrouper.groups(groupEps, by: .season, calendar: utc).map { ["id": $0.id, "title": $0.title, "guids": $0.episodes.map(\.guid)] as J },
                   "year": EpisodeGrouper.groups(groupEps, by: .year, calendar: utc).map { ["id": $0.id, "title": $0.title, "guids": $0.episodes.map(\.guid)] as J },
                   "all": EpisodeGrouper.groups(groupEps, by: .all, calendar: utc).map { ["id": $0.id, "title": $0.title, "guids": $0.episodes.map(\.guid)] as J },
                   "expansionSerialized": { var e = EpisodeGroupExpansion(); e.toggle("season-3", isNewest: true); e.toggle("season-1", isNewest: false); return e.serialized }()]
let sotdDays = ["2026-10-20", "2026-10-21", "2026-10-27", "2026-12-25", "2027-01-01"]
let sotd: [J] = sotdDays.map { d in
    let p = SpinOfTheDay.pick(for: parseISO(d + "T12:00:00Z"), in: bundled, calendar: utc)
    return ["dayKey": d, "catalog": "bundled", "categoryId": opt(p?.category?.id), "movieId": opt(p?.movie.id)]
}
let sotdCat = MovieCatalog(categories: [RouletteCategory(id: "c-empty", name: "Empty", colorHex: "#112233", movieIds: []),
                                         RouletteCategory(id: "c2", name: "Two", colorHex: "#445566", movieIds: ["m2"])],
                            movies: [Movie(id: "m1", title: "M1", year: 2000, genre: "g", categories: ["ghost", "c2"]),
                                     Movie(id: "m2", title: "M2", year: 2000, genre: "g", categories: ["c2"]),
                                     Movie(id: "m3", title: "M3", year: 2000, genre: "g", categories: [])])
var sotdFallback: [J] = []
var seenMovies = Set<String>()
for i in 0..<4000 where seenMovies.count < 3 {
    let d = Calendar(identifier: .gregorian).date(byAdding: .day, value: i, to: parseISO("2026-01-01T12:00:00Z"))!
    let key = SpinOfTheDay.dayKey(for: d, calendar: utc)
    guard SpinOfTheDay.stableHash("category:" + key) % 2 == 0 else { continue }   // day lands on c-empty -> fallback path
    guard let p = SpinOfTheDay.pick(for: d, in: sotdCat, calendar: utc), seenMovies.insert(p.movie.id).inserted else { continue }
    sotdFallback.append(["dayKey": key, "movieId": p.movie.id, "movieCategories": p.movie.categories, "categoryId": opt(p.category?.id)])
}
let sotdFallbackJ: J = ["description": "SPEC §8 / E16: when the day's category has no candidates, the movie comes from the whole catalog and its category is movie.categories.first ONLY if that id is known, otherwise null. There is no search for a later known id (unlike jackpotPick). The widget uses the catalog without deduplicated().",
                        "catalog": catJSON(sotdCat), "cases": sotdFallback]
let hashes: [J] = ["", "a", "category:2026-10-21", "poll:Buzzsprout-19913482", "foobar"].map { ["input": $0, "fnv1a64": String(SpinOfTheDay.stableHash($0))] }
let limit: [J] = [(nil, 0.0), (0, 1), (0, 599.2), (0, 600), (100, 50), (0, 30)].map { (last: Double?, now: Double) in
    let l = SuggestionRateLimit(lastSent: last.map { t0.addingTimeInterval($0) })
    let s = l.secondsRemaining(now: t0.addingTimeInterval(now))
    return ["lastSentOffset": opt(last), "nowOffset": now, "secondsRemaining": opt(s), "canSend": l.canSend(now: t0.addingTimeInterval(now)), "message": s.map(SuggestionRateLimit.message(seconds:)) ?? NSNull()]
}
let emails: [J] = [MovieSuggestion(title: "  Tremors (1990) ", why: "Worms!", category: "Horror"), MovieSuggestion(title: "A+B & C?", why: "", category: nil), MovieSuggestion(title: "   ")].map { m in
    ["title": m.title, "why": m.why, "category": opt(m.category), "isValid": m.isValid, "subject": m.subject, "body": m.body, "mailto": opt(m.mailtoURL?.absoluteString)]
}
let inapp: [J] = [InAppSuggestion(title: " Tremors ", category: " Horror ", note: " Worms ", creditName: " Laura from Ohio "), InAppSuggestion(title: ""), InAppSuggestion(title: String(repeating: "x", count: 121), note: String(repeating: "n", count: 281), creditName: String(repeating: "c", count: 61)), InAppSuggestion(title: "T", category: "", note: "")].map { s in
    ["title": s.title, "category": opt(s.category), "note": s.note, "creditName": s.creditName,
     "expected": ["problems": s.problems.map { "\($0)" }, "isValid": s.isValid, "noteCharactersLeft": s.noteCharactersLeft,
                  "recordFields": ["title": s.trimmedTitle, "category": s.trimmedCategory ?? "", "note": s.trimmedNote, "creditName": s.trimmedCreditName],
                  "asEmail": ["subject": s.asEmail.subject, "body": s.asEmail.body]]]
}
let creditRule: J = [
    "description": "E17 / Q8: every email from the app (Mail compose and mailto) uses InAppSuggestion.asEmail, so the credit is included when filled in. iOS b673df1 appends the credit INTO `why`, so an empty note renders `Why: From: <name>` (bug, 1.0.1 candidate). Shared rule: `From: <credit>` is its own line after `Why:`, or replaces it when the note is empty. Android follows the shared rule.",
    "cases": [["title": "Tremors", "note": "", "creditName": "Laura from Ohio",
               "iosB673df1Body": InAppSuggestion(title: "Tremors", note: "", creditName: "Laura from Ohio").asEmail.body,
               "expectedBody": "Hi MRT Crew,\n\nI’d love to hear you cover:\n\nMovie: Tremors\nFrom: Laura from Ohio\n\nThanks for the show!\n\nSent from the Movie Roulette Tuesday app"] as J,
              ["title": "Tremors", "note": "Worms", "creditName": "Laura from Ohio",
               "iosB673df1Body": InAppSuggestion(title: "Tremors", note: "Worms", creditName: "Laura from Ohio").asEmail.body,
               "expectedBody": "Hi MRT Crew,\n\nI’d love to hear you cover:\n\nMovie: Tremors\nWhy: Worms\nFrom: Laura from Ohio\n\nThanks for the show!\n\nSent from the Movie Roulette Tuesday app"]]]
let halfAndroid: J = [
    "description": "Android main PersonalRatingsTest.halfStarMapping re-run on iOS.",
    "fromLocation": [0.0, 5.0, 15.0, 65.0, 75.0, 250.0, -30.0].enumerated().map { (i, x) in xc("PersonalRatingsTest.halfStarMapping", ["x": x, "width": 100.0], [1, 1, 2, 7, 8, 10, 1][i], HalfStars.fromLocation(x, width: 100)) } + [xc("PersonalRatingsTest.halfStarMapping", ["x": 50.0, "width": 0.0], 1, HalfStars.fromLocation(50, width: 0))],
    "labelStars": [(4.26, "4.5"), (4.24, "4")].map { xc("PersonalRatingsTest.halfStarMapping", $0.0, $0.1, HalfStars.label(stars: HalfStars.roundedToHalf($0.0))) },
    "roundedToHalf": [(3.74, 3.5), (3.75, 4.0)].map { xc("PersonalRatingsTest.halfStarMapping", $0.0, $0.1, HalfStars.roundedToHalf($0.0)) },
    "clamped": [(0, nil), (14, 10)].map { (i: Int, a: Int?) in xc("PersonalRatingsTest.halfStarMapping", i, a, HalfStars.clamped(i)) },
    "fromLegacyStars": [(3, 6), (9, 10)].map { xc("PersonalRatingsTest.halfStarMapping", $0.0, $0.1, HalfStars.fromLegacyStars($0.0)) },
    "resolved": [xc("PersonalRatingsTest.halfStarMapping", ["halfStars": 7, "legacyStars": 4], 7, HalfStars.resolved(halfStars: 7, legacyStars: 4)),
                 xc("PersonalRatingsTest.halfStarMapping", ["halfStars": NSNull(), "legacyStars": 4], 8, HalfStars.resolved(halfStars: nil, legacyStars: 4))],
    "adjusted": [(nil, true, 1), (10, true, 10), (7, false, 6), (1, false, nil)].map { (h: Int?, inc: Bool, a: Int?) in xc("PersonalRatingsTest.halfStarMapping", ["halfStars": opt(h), "increment": inc], a, HalfStars.adjusted(h, increment: inc)) },
]
write("stats.json", [
    "description": "Stats formulas and other pure local logic (SPEC §2.4-2.5, §5, §7-§9). Count ordering follows the shared tie rule (count desc, then id/genre ascending by code point; SPEC §5, Q6), not iOS b673df1 Dictionary order.",
    "catalogForGenres": catJSON(genreCatalog), "snapshots": stats, "historyCompaction": compaction, "halfStars": halfStars, "halfStarsAndroidCrossCheck": halfAndroid, "ratingAggregate": aggs, "personalRatingsSummary": personal,
    "pollTally": polls, "episodeBadge": badge, "newEpisodeAlerts": notify, "episodeGrouping": grouping, "spinOfTheDay": ["description": "SpinOfTheDay.pick for the dayKey (local calendar day; vectors use UTC noon).", "cases": sotd, "stableHash": hashes, "fallbackCategory": sotdFallbackJ],
    "suggestionRateLimit": ["intervalSeconds": SuggestionRateLimit.interval, "cases": limit], "emailSuggestion": ["address": MovieSuggestion.address, "cases": emails], "inAppSuggestion": ["limits": ["title": InAppSuggestion.titleLimit, "note": InAppSuggestion.noteLimit, "creditName": InAppSuggestion.nameLimit], "cases": inapp, "creditLine": creditRule],
])

// MARK: 6. CloudKit
let users = ["_2b5f6c0e9d8a7b6c5d4e3f2a1b0c9d8e", "_abc", ""]
let shaCases: [J] = ["", "abc", "_abcBuzzsprout-19913482.good-bad", "Matt’s pick 🎬"].map { ["input": $0, "sha256hex": SHA256Digest.hex($0)] }
let safe: [J] = ["Buzzsprout-19913482", "the-outsiders-1983", "a b", "émigré", "", String(repeating: "x", count: 120), String(repeating: "x", count: 121), "_leading", "a/b"].map { ["input": $0, "expected": CommunityRecordNames.safeComponent($0)] }
let voteNames: [J] = users.flatMap { u in ["Buzzsprout-19913482.good-bad", "Buzzsprout-19877460.argument", "weird id/with space"].map { p in ["userRecordName": u, "pollId": p, "expected": CommunityRecordNames.vote(pollId: p, userRecordName: u)] as J } }
let ratingNames: [J] = users.flatMap { u in ["the-outsiders-1983", "a b"].map { m in ["userRecordName": u, "movieId": m, "expected": CommunityRecordNames.rating(movieId: m, userRecordName: u)] as J } }
let guids = ["Buzzsprout-19913482", "Buzzsprout-19877460", "Buzzsprout-1", "Buzzsprout-2", "Buzzsprout-3", "weird guid"] + Array(Set(bundled.movies.flatMap(\.episodeIds))).sorted().prefix(6)
let defaultPolls: [J] = guids.map { g in let p = PollFactory.defaultPoll(forEpisode: g, hosts: bundled.showInfo.hosts); return ["episodeGuid": g, "kind": PollFactory.defaultKind(forEpisode: g).rawValue, "pollId": p.id, "question": p.question, "options": p.options.map { ["id": $0.id, "label": $0.label] as J }] }
let overrides = PollOverrides(polls: [.init(episodeGuid: "Buzzsprout-1", question: "Best snack?", options: ["Popcorn", "Nachos", "Candy"], id: "Buzzsprout-1.snack"), .init(episodeGuid: "Buzzsprout-2", question: "Rewatch?", options: ["Yes", "No"]), .init(episodeGuid: "Buzzsprout-3", question: "Only one", options: ["A"])])
let overridePolls: [J] = ["Buzzsprout-1", "Buzzsprout-2", "Buzzsprout-3"].map { g in let p = PollFactory.poll(forEpisode: g, hosts: ["Rachael", "Karl", "Matt"], overrides: overrides); return ["episodeGuid": g, "pollId": p.id, "question": p.question, "options": p.options.map { ["id": $0.id, "label": $0.label] as J }] }
let hostEdge: [J] = [["Rachael", "Karl", "Matt"], ["Solo"], [" A ", "", "B"]].map { hs in
    let g = guids.first { PollFactory.defaultKind(forEpisode: $0) == .argument }!
    return ["episodeGuid": g, "hosts": hs, "options": PollFactory.defaultPoll(forEpisode: g, hosts: hs).options.map { ["id": $0.id, "label": $0.label] as J }]
}
write("cloudkit.json", [
    "description": "CloudKit public-DB record naming and poll ids (SPEC §10). Record names must match byte-for-byte so a listener's vote/rating is overwritten, not duplicated.",
    "container": "iCloud.com.movieroulettetuesday.app", "database": "public",
    "sha256": shaCases, "safeComponent": safe, "voteRecordName": voteNames, "ratingRecordName": ratingNames,
    "defaultPolls": ["hosts": bundled.showInfo.hosts, "cases": defaultPolls, "argumentHostEdgeCases": hostEdge],
    "pollOverrides": ["input": ["polls": [["episodeGuid": "Buzzsprout-1", "question": "Best snack?", "options": ["Popcorn", "Nachos", "Candy"], "id": "Buzzsprout-1.snack"], ["episodeGuid": "Buzzsprout-2", "question": "Rewatch?", "options": ["Yes", "No"]], ["episodeGuid": "Buzzsprout-3", "question": "Only one", "options": ["A"]]]], "cases": overridePolls],
    "ratingFields": (1...10).map { ["halfStars": $0, "starsFieldWritten": HalfStars.roundedStars($0)] as J },
    "suggestionRecord": ["recordType": InAppSuggestion.recordType, "recordNameFormat": "suggestion-<UUID uppercase, from UUID().uuidString>", "fields": ["title", "category", "note", "creditName", "appVersion"], "appVersionFormat": "<CFBundleShortVersionString> (<CFBundleVersion>), e.g. 1.0 (10)"],
])
// MARK: 8. Flows (hand-derived from iOS app code outside RouletteCore; cited file:line at b673df1)
write("flows.json", [
    "description": "State-machine rules that live outside RouletteCore (SwiftUI app code), so they are hand-derived from the cited iOS lines rather than executed. Each case: state + event -> expected effects. Android tests should drive their view model with the same sequences.",
    "catalogRefresh": [
        "source": "ContentView.swift:53-59,75-80; MovieRouletteTuesdayApp.swift:61-63; Roulette/RouletteViewModel.swift:179-198,210,371-373; RouletteCore/RemoteCatalog.swift:176-181",
        "triggers": [
            ["event": "appLaunch", "effect": "load local catalog (cache else bundled), THEN refreshRemoteCatalog()"] as J,
            ["event": "episodeFeedFetchCompleted (episodes.lastFetchedAt changed; includes pull-to-refresh)", "effect": "refreshRemoteCatalog()"],
            ["event": "appForeground (scenePhase active)", "effect": "NO catalog refresh"],
            ["event": "appBackground (scenePhase background)", "effect": "schedule new-episode BG task only (if enabled)"],
            ["event": "refreshRemoteCatalog while another refresh is in flight", "effect": "await the in-flight one; no second request"],
            ["event": "refreshRemoteCatalog < 15 s after the last one STARTED", "effect": "skipped"],
        ],
        "apply": [
            ["state": ["catalog": "nil"] as J, "event": "fresh valid catalog", "expected": "apply now"] as J,
            ["state": ["idle": true] as J, "event": "fresh valid catalog (different)", "expected": "apply now"],
            ["state": ["idle": true] as J, "event": "fresh valid catalog (equal after deduplicated())", "expected": "no-op"],
            ["state": ["isSpinning": true] as J, "event": "fresh valid catalog", "expected": "hold as pending (wheel unchanged)"],
            ["state": ["revealOpen": true] as J, "event": "fresh valid catalog", "expected": "hold as pending"],
            ["state": ["awaitingForcedRespin": true] as J, "event": "fresh valid catalog", "expected": "hold as pending"],
            ["state": ["pending": true, "isSpinning": true] as J, "event": "spin finishes (finishSpin)", "expected": "pending NOT applied"],
            ["state": ["pending": true] as J, "event": "spin finishes on an empty category (notice, no reveal)", "expected": "pending NOT applied; old wheel stays until the next spin starts"],
            ["state": ["pending": true] as J, "event": "reveal dismissed", "expected": "pending applied"],
            ["state": ["pending": true] as J, "event": "next spin starts (user or forced re-spin)", "expected": "pending applied BEFORE the spin target is drawn"],
            ["state": ["any": true] as J, "event": "fresh catalog accepted (applied or pending)", "expected": "widget timeline reload requested (WidgetBridge.catalogUpdated)"],
            ["state": ["any": true] as J, "event": "fetch / decode / validation failure", "expected": "nothing changes; cache untouched"],
            ["state": ["any": true] as J, "event": "valid catalog but cache WRITE fails", "expected": "error swallowed; fresh catalog still applied"],
        ],
    ] as J,
    "spinControls": [
        "source": "Roulette/RouletteView.swift:52,251-252,292,304,310; Roulette/RouletteViewModel.swift:114-118",
        "definitions": ["canSpin": "catalog loaded && !isSpinning && reveal == nil && !awaitingForcedRespin",
                        "canStop": "isSpinning && spinIsStoppable && !isStopping (stoppable = clip-locked spin in flight)"],
        "cases": [
            ["input": "hubButton", "canSpin": true, "canStop": false, "expected": "spin"] as J,
            ["input": "hubButton", "canSpin": false, "canStop": true, "expected": "stopEarly"],
            ["input": "hubButton", "canSpin": false, "canStop": false, "expected": "nothing (disabled)"],
            ["input": "wheelFaceTap", "canSpin": true, "canStop": false, "expected": "spin"],
            ["input": "wheelFaceTap", "canSpin": false, "canStop": true, "expected": "nothing (wheel-tap-to-stop was dropped Oct 15; do not add on Android)"],
            ["input": "magicTap (VoiceOver two-finger double tap; Android: no direct equivalent, map to the accessibility action of the screen)", "canSpin": true, "canStop": false, "expected": "spin"],
            ["input": "magicTap", "canSpin": false, "canStop": true, "expected": "stopEarly"],
            ["input": "accessibilityActivate on the wheel", "canSpin": true, "canStop": false, "expected": "spin"],
            ["input": "accessibilityActivate on the wheel", "canSpin": false, "canStop": true, "expected": "nothing"],
            ["input": "leave the screen mid-spin", "canSpin": false, "canStop": true, "expected": "sound/haptics silenced; the spin still finishes and records exactly once (watchdog)"],
        ],
        "stopEarlyRandomDraws": 2,
    ] as J,
])

// MARK: 7. Single data sources (data/)
func writeData(_ name: String, _ obj: J) {
    var o = obj
    o["_generated"] = ["from": "iOS RouletteCore at \(iosCommit) via tools/vector-gen", "note": "Single source for both ports. Do not edit by hand; change iOS first, then regenerate."]
    let data = try! JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    let dir = outDir.deletingLastPathComponent().appendingPathComponent("data")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try! data.write(to: dir.appendingPathComponent(name))
    print("wrote data/\(name)")
}
writeData("spin-sound-track.json", ["source": "RouletteCore/SpinSoundTrack.swift (generated by mrt-tools/gen_spin_track.py from the recording)", "asset": "wheel-spin.m4a",
    "trimmedLeadingSilence": SpinSoundTrack.trimmedLeadingSilence, "clipDuration": SpinSoundTrack.clipDuration, "stopTime": SpinSoundTrack.stopTime, "brakeDuration": SpinSoundTrack.brakeDuration,
    "spinDuration": SpinSoundTrack.spinDuration, "periodIntercept": SpinSoundTrack.periodIntercept, "periodSlope": SpinSoundTrack.periodSlope, "windUp": SpinSoundTrack.windUp,
    "onsets": SpinSoundTrack.onsets, "onsetCount": SpinSoundTrack.onsets.count, "maxSnap": SpinMotion.maxSnap])
writeData("palette.json", ["source": "RouletteCore/CategoryPalette.swift", "knownCategoryColors": CategoryPalette.known, "fallbackOrder": CategoryPalette.fallback,
    "mutedRule": "unknown id with valid catalog hex: HSB(h, min(s*0.7, 0.5), clamp(b, 0.58, 0.8)); no usable hex: fallbackOrder[fnv1a64(id) % 10]",
    "cleanPro": ["backgroundLight": CleanProColors.backgroundLight, "backgroundDark": CleanProColors.backgroundDark, "spinGradient": CleanProColors.spinGradient, "spinLabelStop": CleanProColors.spinLabelStop,
                 "rimLight": CleanProColors.rimLight, "rimDark": CleanProColors.rimDark, "hubDiscLight": CleanProColors.hubDiscLight, "hubDiscDark": CleanProColors.hubDiscDark,
                 "hubTealLight": CleanProColors.hubTealLight, "hubTealDark": CleanProColors.hubTealDark, "peach": CleanProColors.peach, "pointerLight": CleanProColors.pointerLight,
                 "pointerDark": CleanProColors.pointerDark, "headingLight": CleanProColors.headingLight, "headingDark": CleanProColors.headingDark]])
let show = ShowInfo.mrt
writeData("show.json", ["source": "RouletteCore/Models.swift ShowInfo.mrt, ShowLinks.swift, EpisodeStoreCore.swift, RemoteCatalog.swift",
    "name": show.name, "hosts": show.hosts, "rssURL": opt(show.rssURL?.absoluteString), "applePodcastsURL": opt(show.applePodcastsURL?.absoluteString), "spotifyURL": opt(show.spotifyURL?.absoluteString),
    "applePodcastID": opt(show.applePodcastID), "spotifyShowID": opt(show.spotifyShowID), "buzzsproutShowID": opt(show.buzzsproutShowID),
    "remoteCatalogURL": RemoteCatalog.url.absoluteString, "remoteCatalogTimeoutSeconds": RemoteCatalog.timeout, "feedTimeoutSeconds": EpisodeFeedIO.requestTimeout,
    "suggestionEmail": MovieSuggestion.address, "cloudKitContainer": "iCloud.com.movieroulettetuesday.app", "appGroup": AppGroup.identifier,
    "appleLookupURL": opt(AppleEpisodeLookup.lookupURL()?.absoluteString), "overcastURL": opt(PodcastLinks.overcastShow()?.absoluteString), "buzzsproutURL": opt(PodcastLinks.buzzsproutShow()?.absoluteString),
    "followTheShow": FollowTheShow.links().map { ["title": $0.title, "url": $0.url.absoluteString, "iosSymbol": $0.symbol, "tileHex": $0.tileHex] as J },
    "streamingAttribution": StreamingCatalog.attribution, "tmdbNotice": StreamingCatalog.tmdbNotice, "whereToWatchEmpty": WhereToWatchDisplay.emptyMessage])
print("done")
