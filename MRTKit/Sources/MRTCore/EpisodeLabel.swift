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

    /// Spotify web search for one episode: `https://open.spotify.com/search/<query>`.
    /// The query is the cleaned episode title plus the show name, percent-encoded once
    /// (spaces as `%20`; `+`, `&`, `?`, `#`, `/` never reach Spotify unescaped).
    public static func spotifySearch(episodeTitle: String, show: ShowInfo = .mrt) -> URL? {
        let query = spotifySearchQuery(episodeTitle: episodeTitle)
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: spotifyQueryAllowed),
              !encoded.isEmpty else { return show.spotifyURL }
        return URL(string: "https://open.spotify.com/search/" + encoded)
    }

    public static let spotifyShowName = "Movie Roulette Tuesday"

    /// "S4 · E34 – Romeo + Juliet 🎬" → "Romeo Juliet Movie Roulette Tuesday".
    /// Strips episode-number prefixes, emoji and punctuation that hurt Spotify's matcher,
    /// keeps letters/digits/apostrophes/in-word hyphens, and adds the show name once.
    public static func spotifySearchQuery(episodeTitle: String) -> String {
        let title = cleanEpisodeTitle(episodeTitle)
        if title.range(of: spotifyShowName, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            return title
        }
        return title.isEmpty ? spotifyShowName : "\(title) \(spotifyShowName)"
    }

    static func cleanEpisodeTitle(_ raw: String) -> String {
        var t = raw
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Raw feed GUIDs and sample ids are not titles.
        if t.range(of: #"^Buzzsprout-\d+$"#, options: .regularExpression) != nil { return "" }
        // Leading "S4 · E34 –", "S4E34:", "Ep. 34 -", "Episode 34:", "#34 |" (repeatable).
        let prefix = #"^(?i)\s*(?:s(?:eason)?\s*\d+\s*[·•.:,|\-–—]?\s*)?(?:e(?:p(?:isode)?)?\.?\s*#?\s*\d+|#\s*\d+)\b\s*[·•.:|)\-–—]*\s*"#
        while let r = t.range(of: prefix, options: .regularExpression), !r.isEmpty {
            t.removeSubrange(r)
        }
        // Keep letters, digits, apostrophes inside words and hyphens between letters/digits.
        var out = ""
        let chars = Array(t)
        for (i, c) in chars.enumerated() {
            let prev = i > 0 ? chars[i - 1] : " "
            let next = i + 1 < chars.count ? chars[i + 1] : " "
            if c.isLetter || c.isNumber {
                out.append(c)
            } else if (c == "'" || c == "-") && (prev.isLetter || prev.isNumber) && (next.isLetter || next.isNumber) {
                out.append(c)
            } else {
                out.append(" ")
            }
        }
        return out.split(whereSeparator: { $0 == " " }).joined(separator: " ")
    }

    /// RFC 3986 unreserved only, so everything else is %-escaped exactly once.
    private static let spotifyQueryAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// Buzzsprout episode page when the guid is `Buzzsprout-<numericId>`.
    public static func buzzsproutEpisode(guid: String, show: ShowInfo = .mrt) -> URL? {
        guard let showID = show.buzzsproutShowID,
              guid.hasPrefix("Buzzsprout-"),
              let numeric = Int(guid.dropFirst("Buzzsprout-".count)) else { return nil }
        return URL(string: "https://www.buzzsprout.com/\(showID)/episodes/\(numeric)")
    }
}
