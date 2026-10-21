import Foundation
import Observation
import MRTCore
import MRTShared

/// Cached GUID -> Apple Podcasts episode map from the public iTunes Lookup API
/// (`AppleEpisodeLookup`). Only the show's public Apple ID is sent. Episode
/// pages use the show link until (or unless) the episode is matched.
@MainActor
@Observable
final class AppleEpisodeLinks {
    static let shared = AppleEpisodeLinks()

    private(set) var trackIDs: [String: Int] = [:]
    @ObservationIgnored private var fetchedAt: Date?
    @ObservationIgnored private var inFlight: Task<Void, Never>?

    /// Refresh at most this often, even when an episode is still unmatched
    /// (Apple can lag the RSS feed by a few hours).
    static let minimumRefreshInterval: TimeInterval = 60 * 60

    private struct Cache: Codable {
        var fetchedAt: Date
        var trackIDs: [String: Int]
    }

    private static var cacheURL: URL? {
        try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("apple-episode-lookup.json")
    }

    private init() {
        if let url = Self.cacheURL, let data = try? Data(contentsOf: url),
           let cache = try? JSONDecoder().decode(Cache.self, from: data) {
            trackIDs = cache.trackIDs
            fetchedAt = cache.fetchedAt
        }
    }

    func link(forGUID guid: String, show: ShowInfo = .mrt) -> (url: URL, isExactEpisode: Bool)? {
        AppleEpisodeLookup.link(forGUID: guid, in: trackIDs, show: show)
    }

    /// Fetches when the GUID isn't matched yet and the cache is old enough.
    func ensure(guid: String, show: ShowInfo = .mrt) async {
        if trackIDs[guid] != nil { return }
        if let fetchedAt, Date().timeIntervalSince(fetchedAt) < Self.minimumRefreshInterval { return }
        if let inFlight { await inFlight.value; return }
        let task = Task { await self.refresh(show: show) }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func refresh(show: ShowInfo) async {
        guard let url = AppleEpisodeLookup.lookupURL(show: show) else { return }
        fetchedAt = Date() // also throttles failures
        do {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return }
            let map = try AppleEpisodeLookup.parse(data, show: show)
            guard !map.isEmpty else { return }
            trackIDs = map
            if let cacheURL = Self.cacheURL,
               let encoded = try? JSONEncoder().encode(Cache(fetchedAt: fetchedAt ?? Date(), trackIDs: map)) {
                try? encoded.write(to: cacheURL, options: .atomic)
            }
        } catch {
            // Keep the cached map; the show link remains the fallback.
        }
    }
}
