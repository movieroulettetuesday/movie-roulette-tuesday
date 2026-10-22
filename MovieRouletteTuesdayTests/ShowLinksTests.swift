import XCTest
@testable import MovieRouletteTuesday
import MRTCore

final class ShowLinksTests: XCTestCase {
    private let lookupJSON = """
    {"resultCount":4,"results":[
      {"wrapperType":"track","kind":"podcast","collectionId":1666123849,"trackId":1666123849},
      {"wrapperType":"podcastEpisode","kind":"podcast-episode","collectionId":1666123849,"trackId":1000793365120,"episodeGuid":"Buzzsprout-19913482"},
      {"wrapperType":"podcastEpisode","kind":"podcast-episode","collectionId":1666123849,"trackId":1000792129653,"episodeGuid":" Buzzsprout-19877460 "},
      {"wrapperType":"podcastEpisode","kind":"podcast-episode","collectionId":999,"trackId":5,"episodeGuid":"other-show"}
    ]}
    """

    func testAppleLookupMatchesEpisodesByGUID() throws {
        let map = try AppleEpisodeLookup.parse(Data(lookupJSON.utf8))
        XCTAssertEqual(map, ["Buzzsprout-19913482": 1000793365120, "Buzzsprout-19877460": 1000792129653])
        let exact = try XCTUnwrap(AppleEpisodeLookup.link(forGUID: "Buzzsprout-19913482", in: map))
        XCTAssertTrue(exact.isExactEpisode)
        XCTAssertEqual(exact.url.absoluteString, "https://podcasts.apple.com/us/podcast/id1666123849?i=1000793365120")
    }

    func testAppleLookupFallsBackToShow() throws {
        let fallback = try XCTUnwrap(AppleEpisodeLookup.link(forGUID: "Buzzsprout-1", in: [:]))
        XCTAssertFalse(fallback.isExactEpisode)
        XCTAssertEqual(fallback.url, ShowInfo.mrt.applePodcastsURL)
        XCTAssertThrowsError(try AppleEpisodeLookup.parse(Data("nope".utf8)))
        XCTAssertNil(AppleEpisodeLookup.episodeURL(trackID: 0))
    }

    func testLookupURL() throws {
        let url = try XCTUnwrap(AppleEpisodeLookup.lookupURL())
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(url.host, "itunes.apple.com")
        XCTAssertEqual(items.first { $0.name == "id" }?.value, "1666123849")
        XCTAssertEqual(items.first { $0.name == "entity" }?.value, "podcastEpisode")
    }

    func testListenAndFollowLinks() {
        XCTAssertEqual(PodcastLinks.overcastShow()?.absoluteString, "https://overcast.fm/itunes1666123849")
        XCTAssertEqual(PodcastLinks.buzzsproutShow()?.absoluteString, "https://www.buzzsprout.com/2117292")
        XCTAssertEqual(PodcastLinks.buzzsproutEpisode(guid: "Buzzsprout-19913482")?.absoluteString,
                       "https://www.buzzsprout.com/2117292/episodes/19913482")
        XCTAssertEqual(PodcastLinks.spotifySearch(episodeTitle: "The Outsiders")?.absoluteString,
                       "https://open.spotify.com/search/The%20Outsiders%20Movie%20Roulette%20Tuesday")
        let follow = FollowTheShow.links()
        XCTAssertEqual(follow.count, 8)
        XCTAssertEqual(follow.map(\.url.host), ["podcasts.apple.com", "open.spotify.com", "overcast.fm", "www.buzzsprout.com",
                                               "www.youtube.com", "www.instagram.com", "x.com", "www.facebook.com"])
        XCTAssertEqual(follow[1].url.absoluteString, "https://open.spotify.com/show/0jJt5G1XRlbLYWJuyIQnj1")
        XCTAssertTrue(follow.allSatisfy { $0.url.scheme == "https" })
    }

    func testSuggestionEmail() throws {
        let s = MovieSuggestion(title: "  Tremors ", why: "Kevin Bacon vs. worms.", category: "Horror")
        XCTAssertTrue(s.isValid)
        XCTAssertEqual(s.subject, "Movie suggestion: Tremors")
        XCTAssertTrue(s.body.contains("Movie: Tremors\nWhy: Kevin Bacon vs. worms.\nCategory: Horror"), s.body)
        XCTAssertFalse(MovieSuggestion(title: "Tremors").body.contains("Why:"))
        XCTAssertFalse(MovieSuggestion(title: "Tremors", category: " ").body.contains("Category:"))
        XCTAssertFalse(MovieSuggestion(title: "   ").isValid)
        let url = try XCTUnwrap(MovieSuggestion(title: "A+B & C?").mailtoURL)
        XCTAssertEqual(url.scheme, "mailto")
        let comps = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(comps.path, "theMrtPodcast@gmail.com")
        XCTAssertEqual(comps.queryItems?.first { $0.name == "subject" }?.value, "Movie suggestion: A+B & C?")
    }

    private func ep(_ guid: String, _ day: Int?) -> PodcastEpisode {
        PodcastEpisode(guid: guid, title: guid, pubDate: day.map { Date(timeIntervalSince1970: Double($0) * 86_400) })
    }

    func testNewEpisodeDiff() {
        let feed = [ep("a", 1), ep("b", 2), ep("c", 3)]
        XCTAssertEqual(NewEpisodeDiff.newEpisodes(in: feed, since: nil), [], "first run only sets a baseline")
        let mark = NewEpisodeDiff.watermark(for: feed)
        XCTAssertEqual(mark.latestDate, Date(timeIntervalSince1970: 3 * 86_400))
        XCTAssertEqual(mark.seenGUIDs.first, "c")
        XCTAssertEqual(NewEpisodeDiff.newEpisodes(in: feed, since: mark), [])
        let later = feed + [ep("d", 4), ep("e", 5), ep("old-undated", nil)]
        XCTAssertEqual(NewEpisodeDiff.newEpisodes(in: later, since: mark).map(\.guid), ["e", "d"])
        // A re-dated old episode (already seen) never alerts again.
        XCTAssertEqual(NewEpisodeDiff.newEpisodes(in: [ep("c", 9)], since: mark), [])
        XCTAssertEqual(NewEpisodeDiff.notificationText(for: [ep("d", 4)])?.body, "d")
        XCTAssertEqual(NewEpisodeDiff.notificationText(for: [ep("e", 5), ep("d", 4)])?.title, "2 new episodes of Movie Roulette Tuesday")
        XCTAssertNil(NewEpisodeDiff.notificationText(for: []))
    }

    // MARK: Spotify episode search (real titles from rss.buzzsprout.com/2117292.rss)

    func testSpotifyQueryRealTitles() {
        let cases: [(String, String)] = [
            ("The Outsiders", "The Outsiders Movie Roulette Tuesday"),
            ("Palmer Rockey's SCARLET WARNING 666", "Palmer Rockey's SCARLET WARNING 666 Movie Roulette Tuesday"),
            ("Romeo + Juliet", "Romeo Juliet Movie Roulette Tuesday"),
            ("Rock & Rule", "Rock Rule Movie Roulette Tuesday"),
            ("Mad Max: Fury Road", "Mad Max Fury Road Movie Roulette Tuesday"),
            ("O Brother, Where Art Thou?", "O Brother Where Art Thou Movie Roulette Tuesday"),
            ("Three Billboards Outside Ebbing, Missouri", "Three Billboards Outside Ebbing Missouri Movie Roulette Tuesday"),
            ("Kon-Tiki", "Kon-Tiki Movie Roulette Tuesday"),
            ("Cry-Baby", "Cry-Baby Movie Roulette Tuesday"),
            ("π", "π Movie Roulette Tuesday"),
            ("Season 3: Year In Review", "Season 3 Year In Review Movie Roulette Tuesday"),
            ("Return of the Living Dead 3", "Return of the Living Dead 3 Movie Roulette Tuesday"),
            // Show name already in the title: not duplicated.
            ("What is Movie Roulette Tuesday?", "What is Movie Roulette Tuesday"),
        ]
        for (title, expected) in cases {
            XCTAssertEqual(PodcastLinks.spotifySearchQuery(episodeTitle: title), expected, title)
        }
    }

    func testSpotifyQueryStripsPrefixesAndEmoji() {
        let cases: [(String, String)] = [
            ("S4 · E34 – The Outsiders", "The Outsiders Movie Roulette Tuesday"),
            ("S4E34: The Outsiders 🎬", "The Outsiders Movie Roulette Tuesday"),
            ("Ep. 11 - Romeo + Juliet", "Romeo Juliet Movie Roulette Tuesday"),
            ("Episode 34: The Outsiders", "The Outsiders Movie Roulette Tuesday"),
            ("#29 | Crash", "Crash Movie Roulette Tuesday"),
            ("  Palmer Rockey\u{2019}s SCARLET WARNING 666 🔥 ", "Palmer Rockey's SCARLET WARNING 666 Movie Roulette Tuesday"),
            // Titles that merely start with numbers or E. are left alone.
            ("12 Angry Men", "12 Angry Men Movie Roulette Tuesday"),
            ("2001: A Space Odyssey", "2001 A Space Odyssey Movie Roulette Tuesday"),
            ("E.T. the Extra-Terrestrial", "E T the Extra-Terrestrial Movie Roulette Tuesday"),
            // Fallback labels that are not real titles fall back to the show.
            ("Episode 12", "Movie Roulette Tuesday"),
            ("Buzzsprout-19913482", "Movie Roulette Tuesday"),
            ("", "Movie Roulette Tuesday"),
        ]
        for (title, expected) in cases {
            XCTAssertEqual(PodcastLinks.spotifySearchQuery(episodeTitle: title), expected, title)
        }
    }

    func testSpotifySearchURLEncodedOnce() throws {
        let cases: [(String, String)] = [
            ("Romeo + Juliet", "Romeo%20Juliet%20Movie%20Roulette%20Tuesday"),
            ("Palmer Rockey's SCARLET WARNING 666", "Palmer%20Rockey%27s%20SCARLET%20WARNING%20666%20Movie%20Roulette%20Tuesday"),
            ("Kon-Tiki", "Kon-Tiki%20Movie%20Roulette%20Tuesday"),
            ("π", "%CF%80%20Movie%20Roulette%20Tuesday"),
        ]
        for (title, path) in cases {
            let url = try XCTUnwrap(PodcastLinks.spotifySearch(episodeTitle: title), title)
            XCTAssertEqual(url.absoluteString, "https://open.spotify.com/search/" + path, title)
            XCTAssertFalse(url.absoluteString.contains("%25"), "double-encoded: \(url)")
            XCTAssertFalse(url.absoluteString.contains("+"), "\(url)")
            // Spotify decodes the path once and must get the clean query back.
            XCTAssertEqual(url.path, "/search/" + PodcastLinks.spotifySearchQuery(episodeTitle: title), title)
        }
    }
}


final class InAppSuggestionTests: XCTestCase {
    func testValidation() {
        XCTAssertEqual(InAppSuggestion(title: "   ").problems, [.missingTitle])
        XCTAssertTrue(InAppSuggestion(title: " Tremors ", note: "Graboids.").isValid)
        let long = String(repeating: "x", count: 281)
        XCTAssertEqual(InAppSuggestion(title: "T", note: long).problems, [.noteTooLong])
        XCTAssertTrue(InAppSuggestion(title: "T", note: String(repeating: "x", count: 280)).isValid)
        XCTAssertEqual(InAppSuggestion(title: "T", creditName: String(repeating: "n", count: 61)).problems, [.nameTooLong])
        XCTAssertEqual(InAppSuggestion(title: String(repeating: "t", count: 121)).problems, [.titleTooLong])
        XCTAssertEqual(InAppSuggestion(title: "T", note: "abc").noteCharactersLeft, 277)
        XCTAssertEqual(InAppSuggestion.capped(long, to: 280).count, 280)
        XCTAssertEqual(InAppSuggestion.capped("short", to: 280), "short")
        XCTAssertNil(InAppSuggestion(title: "T", category: "  ").trimmedCategory)
    }

    func testEmailFallbackCarriesTheSamePick() throws {
        let s = InAppSuggestion(title: "Tremors", category: "Cult", note: "Graboids.", creditName: "Laura from Ohio")
        let mail = s.asEmail
        XCTAssertEqual(mail.subject, "Movie suggestion: Tremors")
        XCTAssertTrue(mail.body.contains("Graboids."))
        XCTAssertTrue(mail.body.contains("From: Laura from Ohio"))
        XCTAssertTrue(mail.body.contains("Category: Cult"))
        XCTAssertEqual(try XCTUnwrap(mail.mailtoURL).scheme, "mailto")
    }

    /// 1.0.1: with a credit and no note the body must not read "Why: From: <name>".
    func testEmptyNoteWithCreditHasNoWhyLine() {
        let mail = InAppSuggestion(title: "Tremors", note: "  ", creditName: " Laura from Ohio ").asEmail
        XCTAssertFalse(mail.body.contains("Why:"))
        XCTAssertFalse(mail.body.contains("Why: From:"))
        XCTAssertEqual(mail.body, [
            "Hi MRT Crew,", "", "I’d love to hear you cover:", "",
            "Movie: Tremors", "From: Laura from Ohio",
            "", "Thanks for the show!", "", "Sent from the Movie Roulette Tuesday app",
        ].joined(separator: "\n"))
    }

    func testNoteAndCreditAreSeparateLines() {
        let mail = InAppSuggestion(title: "Tremors", category: "Cult", note: "Graboids.", creditName: "Laura").asEmail
        XCTAssertEqual(mail.why, "Graboids.")
        XCTAssertEqual(mail.credit, "Laura")
        XCTAssertTrue(mail.body.contains("Movie: Tremors\nWhy: Graboids.\nFrom: Laura\nCategory: Cult\n"))
        // No credit: no From line; no note and no credit: neither line.
        XCTAssertFalse(InAppSuggestion(title: "T", note: "n").asEmail.body.contains("From:"))
        let bare = InAppSuggestion(title: "T").asEmail.body
        XCTAssertFalse(bare.contains("Why:") || bare.contains("From:"))
        XCTAssertNil(InAppSuggestion(title: "T", creditName: "   ").asEmail.credit)
    }

    func testRateLimitOnePerTenMinutes() {
        let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
        var limit = SuggestionRateLimit()
        XCTAssertTrue(limit.canSend(now: t0))
        limit.recordSend(now: t0)
        XCTAssertFalse(limit.canSend(now: t0.addingTimeInterval(60)))
        XCTAssertEqual(limit.secondsRemaining(now: t0.addingTimeInterval(60)), 540)
        XCTAssertEqual(limit.secondsRemaining(now: t0.addingTimeInterval(599.5)), 1)
        XCTAssertTrue(limit.canSend(now: t0.addingTimeInterval(600)))
        XCTAssertTrue(limit.canSend(now: t0.addingTimeInterval(-5)), "clock moved back: never stuck")
        XCTAssertEqual(SuggestionRateLimit.message(seconds: 540), "You just sent one. Try again in 9 min.")
    }

    func testRateLimitPersists() {
        let defaults = UserDefaults(suiteName: "mrt-test-ratelimit-\(UUID().uuidString)")!
        XCTAssertNil(SuggestionRateLimit.load(from: defaults).lastSent)
        var limit = SuggestionRateLimit()
        let now = Date()
        limit.recordSend(now: now)
        limit.save(to: defaults)
        XCTAssertFalse(SuggestionRateLimit.load(from: defaults).canSend(now: now.addingTimeInterval(10)))
    }
}
