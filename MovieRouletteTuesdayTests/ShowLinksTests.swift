import XCTest
@testable import MovieRouletteTuesday

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
        let spotify = PodcastLinks.spotifySearch(episodeTitle: "The Outsiders")?.absoluteString ?? ""
        XCTAssertTrue(spotify.hasPrefix("https://open.spotify.com/search/"), spotify)
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
}
