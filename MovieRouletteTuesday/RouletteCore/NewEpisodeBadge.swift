import Foundation

/// Episodes-tab badge: how many feed episodes are newer than the last time
/// the tab was viewed. The timestamp lives only on this device.
public enum NewEpisodeBadge {
    /// Episodes published strictly after `lastViewed`. No baseline yet -> 0
    /// (never badge the whole back catalog).
    public static func count(episodes: [PodcastEpisode], lastViewed: Date?) -> Int {
        guard let lastViewed else { return 0 }
        return episodes.reduce(0) { n, ep in
            guard let date = ep.pubDate, date > lastViewed else { return n }
            return n + 1
        }
    }

    /// First-launch baseline: the newest episode date (so nothing already in the
    /// feed counts as new), or `now` if the feed has no dates.
    public static func initialBaseline(episodes: [PodcastEpisode], now: Date = Date()) -> Date {
        episodes.compactMap(\.pubDate).max() ?? now
    }

    /// Value to store when the tab is viewed: `now`, but never earlier than the
    /// newest episode (guards against pubDates slightly in the future).
    public static func viewedTimestamp(episodes: [PodcastEpisode], now: Date = Date()) -> Date {
        max(now, episodes.compactMap(\.pubDate).max() ?? now)
    }
}
