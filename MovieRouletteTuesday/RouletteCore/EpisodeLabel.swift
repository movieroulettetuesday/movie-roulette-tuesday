import Foundation

/// Turns movie ↔ episode links into display text using the catalog and/or feed.
public enum EpisodeLabel {
    public static let samplePrefix = "sample-ep-"

    public static func sampleEpisodeNumber(from episodeId: String) -> Int? {
        guard episodeId.hasPrefix(samplePrefix) else { return nil }
        return Int(episodeId.dropFirst(samplePrefix.count))
    }

    /// Resolve a Buzzsprout guid (or sample id) to a human title.
    public static func title(
        forEpisodeId id: String,
        movie: Movie? = nil,
        episodesByGUID: [String: PodcastEpisode] = [:]
    ) -> String {
        if let episode = episodesByGUID[id] { return episode.title }
        if let movie, movie.episodeIds.first == id, let title = movie.episodeTitle { return title }
        if let movie, let title = movie.episodeTitle, movie.episodeIds.contains(id) { return title }
        if let n = sampleEpisodeNumber(from: id) { return "Episode \(n)" }
        return id
    }

    /// "Discussed on The Outsiders (S4E34)", etc.
    public static func discussedText(
        for movie: Movie,
        episodesByGUID: [String: PodcastEpisode] = [:]
    ) -> String {
        let ids = movie.episodeIds
        guard !ids.isEmpty else { return "Not discussed on the show yet" }

        if let numbers = Optional(ids.compactMap(sampleEpisodeNumber(from:))),
           numbers.count == ids.count, !numbers.isEmpty {
            let suffix = " (sample)"
            switch numbers.count {
            case 1: return "Discussed on Episode \(numbers[0])" + suffix
            case 2: return "Discussed on Episodes \(numbers[0]) & \(numbers[1])" + suffix
            default: return "Discussed on Episode \(numbers[0]) + \(numbers.count - 1) more" + suffix
            }
        }

        func label(for id: String) -> String {
            let title = title(forEpisodeId: id, movie: movie, episodesByGUID: episodesByGUID)
            if let se = episodesByGUID[id]?.seasonEpisodeLabel {
                return "\(title) (\(se))"
            }
            return title
        }

        switch ids.count {
        case 1:
            return "Discussed on \(label(for: ids[0]))"
        case 2:
            return "Discussed on \(label(for: ids[0])) & \(label(for: ids[1]))"
        default:
            return "Discussed on \(label(for: ids[0])) + \(ids.count - 1) more"
        }
    }
}

/// Deep links into Apple Podcasts / Spotify / Buzzsprout (no API keys).
public enum PodcastLinks {
    public static func appleShow(show: ShowInfo = .mrt) -> URL? {
        show.applePodcastsURL
    }

    public static func spotifyShow(show: ShowInfo = .mrt) -> URL? {
        show.spotifyURL
    }

    /// Apple Podcasts search for this episode within the show.
    public static func appleSearch(episodeTitle: String, show: ShowInfo = .mrt) -> URL? {
        var parts = ["Movie Roulette Tuesday", episodeTitle]
        if let id = show.applePodcastID { parts.append(id) }
        var comps = URLComponents(string: "https://podcasts.apple.com/us/search")
        comps?.queryItems = [URLQueryItem(name: "term", value: parts.joined(separator: " "))]
        return comps?.url
    }

    public static func spotifySearch(episodeTitle: String) -> URL? {
        var comps = URLComponents(string: "https://open.spotify.com/search")
        // Spotify web search path-encodes the query.
        let q = "Movie Roulette Tuesday \(episodeTitle)"
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        comps?.path = "/search/" + q
        return comps?.url ?? URL(string: "https://open.spotify.com/search/\(q)")
    }

    /// Buzzsprout episode page when the guid is `Buzzsprout-<numericId>`.
    public static func buzzsproutEpisode(guid: String, show: ShowInfo = .mrt) -> URL? {
        guard let showID = show.buzzsproutShowID,
              guid.hasPrefix("Buzzsprout-"),
              let numeric = Int(guid.dropFirst("Buzzsprout-".count)) else { return nil }
        return URL(string: "https://www.buzzsprout.com/\(showID)/episodes/\(numeric)")
    }
}
