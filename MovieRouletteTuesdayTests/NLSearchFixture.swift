import Foundation
@testable import MovieRouletteTuesday

/// Fixed catalog, episodes, ratings, and services for NL search `apply`
/// tests. Small on purpose so every expected result is checked by hand.
enum NLSearchFixture {
    static let shudder = StreamingInfo.Provider(id: 99, name: "Shudder")
    static let shudderChannel = StreamingInfo.Provider(id: 204, name: "Shudder Amazon Channel")
    static let netflix = StreamingInfo.Provider(id: 8, name: "Netflix")
    static let netflixAds = StreamingInfo.Provider(id: 1796, name: "Netflix Standard with Ads")
    static let hboMax = StreamingInfo.Provider(id: 1899, name: "HBO Max")
    static let hulu = StreamingInfo.Provider(id: 15, name: "Hulu")
    static let disney = StreamingInfo.Provider(id: 337, name: "Disney Plus")
    static let paramount = StreamingInfo.Provider(id: 2303, name: "Paramount Plus Premium")
    static let criterionChannel = StreamingInfo.Provider(id: 258, name: "Criterion Channel")
    static let tubi = StreamingInfo.Provider(id: 73, name: "Tubi TV")
    static let pluto = StreamingInfo.Provider(id: 300, name: "Pluto TV")
    static let kanopy = StreamingInfo.Provider(id: 191, name: "Kanopy")
    static let vudu = StreamingInfo.Provider(id: 7, name: "Vudu")

    static func catalog() -> MovieCatalog {
        let movies = [
            Movie(id: "the-thing-1982", title: "The Thing", year: 1982, genre: "Horror",
                  categories: ["cat-horror", "cat-cult"], episodeIds: ["ep-thing"],
                  streaming: StreamingInfo(stream: [shudder], free: [tubi])),
            Movie(id: "the-thing-2011", title: "The Thing", year: 2011, genre: "Horror",
                  categories: ["cat-horror"], streaming: StreamingInfo(stream: [netflixAds])),
            Movie(id: "the-devils-rain-1975", title: "The Devil's Rain", year: 1975, genre: "Horror",
                  categories: ["cat-horror", "cat-cult"], episodeIds: ["ep-s4e39"],
                  streaming: StreamingInfo(stream: [shudderChannel], free: [pluto], rent: [vudu])),
            Movie(id: "the-evil-dead-1981", title: "The Evil Dead", year: 1981, genre: "Horror",
                  categories: ["cat-horror"], streaming: StreamingInfo(free: [tubi, pluto])),
            Movie(id: "hellraiser-1987", title: "Hellraiser", year: 1987, genre: "Horror",
                  categories: ["cat-horror"], episodeIds: ["ep-s4e40"], streaming: StreamingInfo(free: [tubi])),
            Movie(id: "alien-1979", title: "Alien", year: 1979, genre: "Sci-Fi",
                  categories: ["cat-scifi", "cat-horror"], episodeIds: ["ep-alien"],
                  streaming: StreamingInfo(stream: [hboMax], rent: [vudu])),
            Movie(id: "blade-runner-1982", title: "Blade Runner", year: 1982, genre: "Sci-Fi",
                  categories: ["cat-scifi", "cat-criterion"], streaming: StreamingInfo(stream: [netflix])),
            Movie(id: "seven-samurai-1954", title: "Seven Samurai", year: 1954, genre: "Drama",
                  categories: ["cat-criterion"], streaming: StreamingInfo(stream: [criterionChannel], free: [kanopy])),
            Movie(id: "the-godfather-1972", title: "The Godfather", year: 1972, genre: "Drama",
                  categories: ["cat-prestige"], streaming: StreamingInfo(stream: [paramount])),
            Movie(id: "heathers-1989", title: "Heathers", year: 1989, genre: "Comedy",
                  categories: ["cat-dark-comedy"], streaming: StreamingInfo(stream: [hulu])),
            Movie(id: "titanic-1997", title: "Titanic", year: 1997, genre: "Romance",
                  categories: ["cat-love"], streaming: StreamingInfo(stream: [disney])),
            Movie(id: "eternal-sunshine-2004", title: "Eternal Sunshine of the Spotless Mind", year: 2004, genre: "Romance",
                  categories: ["cat-love", "cat-listener"], streaming: StreamingInfo(stream: [netflix])),
            Movie(id: "the-room-2003", title: "The Room", year: 2003, genre: "Drama",
                  categories: ["cat-listener", "cat-cult"], streaming: StreamingInfo(free: [tubi], rent: [vudu])),
            Movie(id: "pulp-fiction-1994", title: "Pulp Fiction", year: 1994, genre: "Thriller",
                  categories: ["cat-action", "cat-listener"], streaming: StreamingInfo(stream: [hboMax])),
            Movie(id: "die-hard-1988", title: "Die Hard", year: 1988, genre: "Action",
                  categories: ["cat-action"], streaming: StreamingInfo(rent: [vudu])),
            Movie(id: "the-shining-1980", title: "The Shining", year: 1980, genre: "Horror",
                  categories: ["cat-horror", "cat-criterion"]),
        ]
        let categories = NLSearch.categories.map { c in
            RouletteCategory(
                id: c.id, name: c.name, fullName: c.fullName, colorHex: "#808080",
                movieIds: movies.filter { $0.categories.contains(c.id) }.map(\.id)
            )
        }
        return MovieCatalog(categories: categories, movies: movies)
    }

    /// Newest first, like the feed.
    static func episodes() -> [PodcastEpisode] {
        func day(_ text: String) -> Date { ISO8601DateFormatter().date(from: text + "T12:00:00Z")! }
        return [
            PodcastEpisode(guid: "ep-s4e40", title: "Hellraiser", pubDate: day("2026-03-10"), season: 4, episode: 40),
            PodcastEpisode(guid: "ep-s4e39", title: "The Devil's Rain", pubDate: day("2026-03-03"), season: 4, episode: 39,
                           summary: "Karl and Rachael talk Satanists."),
            PodcastEpisode(guid: "ep-bonus", title: "Bonus: Listener Mailbag", pubDate: day("2025-12-24"),
                           summary: "Karl answers Shudder questions."),
            PodcastEpisode(guid: "ep-thing", title: "The Thing", pubDate: day("2025-06-03"), season: 3, episode: 10),
            PodcastEpisode(guid: "ep-alien", title: "Alien", pubDate: day("2024-02-06"), season: 2, episode: 5),
        ]
    }

    /// Rating a movie marks it watched (PersonalRatings rule), so a rated
    /// movie is unwatched only when its status is then set to the watchlist.
    static func ratings() -> PersonalRatings {
        var r = PersonalRatings()
        let t = Date(timeIntervalSinceReferenceDate: 0)
        r.setHalfStars(10, for: "the-thing-1982", now: t); r.setStatus(.watched, for: "the-thing-1982", now: t)
        r.setHalfStars(7, for: "the-devils-rain-1975", now: t); r.setStatus(.wantToWatch, for: "the-devils-rain-1975", now: t)
        r.setHalfStars(8, for: "alien-1979", now: t); r.setStatus(.watched, for: "alien-1979", now: t)
        r.setHalfStars(9, for: "blade-runner-1982", now: t); r.setStatus(.wantToWatch, for: "blade-runner-1982", now: t)
        r.setHalfStars(10, for: "the-godfather-1972", now: t); r.setStatus(.watched, for: "the-godfather-1972", now: t)
        r.setHalfStars(6, for: "heathers-1989", now: t); r.setStatus(.watched, for: "heathers-1989", now: t)
        r.setStatus(.wantToWatch, for: "titanic-1997", now: t)
        r.setHalfStars(4, for: "pulp-fiction-1994", now: t)
        r.setStatus(.watched, for: "the-evil-dead-1981", now: t)
        r.setHalfStars(2, for: "the-room-2003", now: t)
        return r
    }

    /// Shudder, HBO Max, Hulu.
    static let services = MyServices(ids: [99, 1899, 15])

    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
}
