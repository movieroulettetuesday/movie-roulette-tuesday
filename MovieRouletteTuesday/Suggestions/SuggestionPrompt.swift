import Foundation

/// One compact catalog row for the on-device prompt. No plots, no URLs, no raw JSON.
struct SuggestionMovieContext: Equatable, Sendable {
    var id: String
    var title: String
    var year: Int
    var genre: String
    var categories: [String]
    var onWatchlist: Bool
    var halfStars: Int?
    var recentSpin: Bool
    var onServices: [String]
}

struct SuggestionContext: Equatable, Sendable {
    /// Names of the listener’s “My Services,” in a stable order. Empty if none are chosen.
    var serviceNames: [String]
    var movies: [SuggestionMovieContext]
}

enum SuggestionPrompt {
    static let instructions = """
        Pick one catalog movie for the listener to watch tonight.
        Prefer watchlist titles that are also on the listener’s services.
        Weigh their ratings (rated is half-stars; 10 is five stars).
        Avoid movies marked recent (spun very recently).
        Do not invent a movie. Copy movieId exactly from the catalog list.
        Write a short why — one or two sentences — using only the facts given (watchlist, rating, genre, or a service they have). Do not overstate a rating or a provider.
        """

    /// Most recent distinct movie ids, newest first, up to `limit`. Sorted by timestamp, not array order.
    static func recentIDs(from results: [SpinResult], limit: Int = 10) -> Set<String> {
        let ordered = results.sorted { $0.timestamp > $1.timestamp }
        var seen = Set<String>()
        var ids: [String] = []
        for result in ordered {
            if seen.insert(result.movieId).inserted {
                ids.append(result.movieId)
                if ids.count >= limit { break }
            }
        }
        return Set(ids)
    }

    static func context(
        catalog: MovieCatalog,
        ratings: PersonalRatings,
        recentIDs: Set<String>,
        services: MyServices
    ) -> SuggestionContext {
        let knownNames = Dictionary(
            uniqueKeysWithValues: StreamingCatalog.services(in: catalog.movies).map { ($0.id, $0.name) }
        )
        let serviceNames = services.ids.sorted().compactMap { knownNames[$0] }
        let movies = catalog.movies.map { movie in
            let categories = movie.categories.compactMap { catalog.category(withId: $0)?.displayName }
            let on = StreamingCatalog.matchingServices(movie, services: services).map(\.name)
            return SuggestionMovieContext(
                id: movie.id,
                title: movie.title,
                year: movie.year,
                genre: movie.genre,
                categories: categories,
                onWatchlist: ratings.status(for: movie.id) == .wantToWatch,
                halfStars: ratings.halfStars(for: movie.id),
                recentSpin: recentIDs.contains(movie.id),
                onServices: on
            )
        }
        return SuggestionContext(serviceNames: serviceNames, movies: movies)
    }

    static func prompt(from context: SuggestionContext) -> String {
        var lines: [String] = []
        if context.serviceNames.isEmpty {
            lines.append("Listener’s services: (none chosen)")
        } else {
            lines.append("Listener’s services: " + context.serviceNames.joined(separator: ", "))
        }
        lines.append("Catalog:")
        for movie in context.movies {
            lines.append(line(for: movie))
        }
        lines.append("Pick one movie for tonight.")
        return lines.joined(separator: "\n")
    }

    static func line(for movie: SuggestionMovieContext) -> String {
        var parts = [
            "id=\(movie.id)",
            "title=\(movie.title)",
            "year=\(movie.year)",
            "genre=\(movie.genre)",
        ]
        if !movie.categories.isEmpty {
            parts.append("categories=\(movie.categories.joined(separator: ","))")
        }
        if movie.onWatchlist { parts.append("watchlist") }
        if let half = movie.halfStars { parts.append("rated=\(HalfStars.label(half))") }
        if movie.recentSpin { parts.append("recent") }
        if !movie.onServices.isEmpty {
            parts.append("on=\(movie.onServices.joined(separator: ","))")
        }
        return parts.joined(separator: "|")
    }
}
