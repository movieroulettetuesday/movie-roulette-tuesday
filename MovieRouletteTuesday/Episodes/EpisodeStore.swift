import Foundation
import Observation
import MRTCore
import MRTShared

/// Loads the Buzzsprout RSS feed, caches it under Application Support, and
/// exposes episodes to the Episodes tab + reveal sheet.
@MainActor
@Observable
final class EpisodeStore {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded(fromCache: Bool)
        case failed(String)
    }

    private(set) var episodes: [PodcastEpisode] = []
    private(set) var feedTitle: String = ""
    /// Show artwork from the feed (channel itunes:image); fallback for episodes
    /// and movies without their own art. nil from caches older than artwork support.
    private(set) var showArtworkURL: URL?
    private(set) var loadState: LoadState = .idle
    private(set) var lastFetchedAt: Date?
    private(set) var lastError: String?
    /// Last time the Episodes tab was viewed (local only). Drives the tab badge.
    private(set) var lastViewedAt: Date?

    private let feedURL: URL
    private let cacheURL: URL?
    private let defaults: UserDefaults
    static let lastViewedKey = "episodes.lastViewedAt"

    init(
        feedURL: URL = EpisodeFeedIO.defaultFeedURL,
        cacheURL: URL? = try? EpisodeFeedIO.cacheURL(),
        defaults: UserDefaults = .standard
    ) {
        self.feedURL = feedURL
        self.cacheURL = cacheURL
        self.defaults = defaults
        self.lastViewedAt = defaults.object(forKey: Self.lastViewedKey) as? Date
    }

    /// Episodes published since the Episodes tab was last viewed.
    var newEpisodeCount: Int {
        NewEpisodeBadge.count(episodes: episodes, lastViewed: lastViewedAt)
    }

    /// Clears the badge. No-op until the feed has loaded (the first load sets
    /// the baseline instead, so the back catalog never counts as new).
    func markViewed(now: Date = Date()) {
        guard !episodes.isEmpty else { return }
        setLastViewed(NewEpisodeBadge.viewedTimestamp(episodes: episodes, now: now))
    }

    private func setLastViewed(_ date: Date) {
        lastViewedAt = date
        defaults.set(date, forKey: Self.lastViewedKey)
    }

    /// guid -> episode. Built once per feed update (it used to be rebuilt on
    /// every access) and duplicate-safe.
    private(set) var episodesByGUID: [String: PodcastEpisode] = [:]

    func episode(guid: String) -> PodcastEpisode? {
        episodesByGUID[guid]
    }

    /// A network refresh newer than this is reused when a screen appears;
    /// pull-to-refresh / Try Again always go to the network.
    static let freshness: TimeInterval = 5 * 60
    @ObservationIgnored private var inFlight: Task<Void, Never>?
    @ObservationIgnored private var lastNetworkSuccess: Date?

    /// Load cache first (instant offline), then refresh from the network.
    /// Overlapping calls (app launch, tab appear, pull-to-refresh) share one
    /// in-flight request instead of starting parallel fetches.
    func load(forceNetwork: Bool = false) async {
        if let inFlight {
            await inFlight.value
            return
        }
        if !forceNetwork, let lastNetworkSuccess,
           Date().timeIntervalSince(lastNetworkSuccess) < Self.freshness {
            return
        }
        let task = Task { await self.performLoad(forceNetwork: forceNetwork) }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func performLoad(forceNetwork: Bool) async {
        if !forceNetwork, episodes.isEmpty,
           let cached = await EpisodeFeedIO.loadCacheIfPresent(from: cacheURL) {
            apply(cached, fromCache: true)
        }

        loadState = .loading
        do {
            let fresh = try await EpisodeFeedIO.refresh(from: feedURL, cacheURL: cacheURL)
            lastNetworkSuccess = Date()
            apply(fresh, fromCache: false)
        } catch {
            let message = Self.friendlyMessage(for: error)
            if episodes.isEmpty {
                loadState = .failed(message)
            } else {
                // Keep showing cache; surface a soft error.
                lastError = message
                loadState = .loaded(fromCache: true)
            }
        }
    }

    static func friendlyMessage(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                return "You’re offline. Showing saved episodes."
            case .timedOut:
                return "Loading episodes took too long. Pull down to try again."
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "Couldn’t load episodes. Pull down to try again."
            default:
                break
            }
        }
        if error is RSSFeedError { return "Couldn’t read the episode list. Pull down to try again." }
        return error.localizedDescription
    }

    private func apply(_ cache: CachedEpisodeFeed, fromCache: Bool) {
        let unique = PodcastEpisode.uniqued(cache.episodes)
        episodes = unique
        episodesByGUID = PodcastEpisode.byGUID(unique)
        feedTitle = cache.title
        showArtworkURL = cache.artworkURL
        lastFetchedAt = cache.fetchedAt
        lastError = nil
        loadState = .loaded(fromCache: fromCache)
        if lastViewedAt == nil, !unique.isEmpty {
            // First launch: don't badge the entire back catalog.
            setLastViewed(NewEpisodeBadge.initialBaseline(episodes: unique))
        }
        WidgetBridge.publishLatestEpisode(from: unique)
    }
}
