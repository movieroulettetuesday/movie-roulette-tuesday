import Foundation

// MARK: - Apple Podcasts per-episode links

/// Maps RSS episode GUIDs to exact Apple Podcasts episode links using Apple's
/// public, keyless iTunes Lookup API. Only the show's Apple ID is sent (no user
/// data). Any episode that isn't matched falls back to the show page.
public enum AppleEpisodeLookup {
    /// One request covers the whole back catalog (Apple caps `limit` at 200).
    public static func lookupURL(show: ShowInfo = .mrt, limit: Int = 200) -> URL? {
        guard let id = show.applePodcastID, !id.isEmpty else { return nil }
        var comps = URLComponents(string: "https://itunes.apple.com/lookup")
        comps?.queryItems = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "entity", value: "podcastEpisode"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        return comps?.url
    }

    /// `https://podcasts.apple.com/us/podcast/id<show>?i=<track>`.
    public static func episodeURL(trackID: Int, show: ShowInfo = .mrt) -> URL? {
        guard let id = show.applePodcastID, !id.isEmpty, trackID > 0 else { return nil }
        return URL(string: "https://podcasts.apple.com/us/podcast/id\(id)?i=\(trackID)")
    }

    private struct Response: Decodable {
        struct Item: Decodable {
            let wrapperType: String?
            let kind: String?
            let trackId: Int?
            let episodeGuid: String?
            let collectionId: Int?
        }
        let results: [Item]
    }

    /// GUID -> Apple track id, only for episodes of this show.
    public static func parse(_ data: Data, show: ShowInfo = .mrt) throws -> [String: Int] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        let showID = show.applePodcastID.flatMap(Int.init)
        var map: [String: Int] = [:]
        for item in response.results {
            guard item.wrapperType == "podcastEpisode" || item.kind == "podcast-episode",
                  let guid = item.episodeGuid?.trimmingCharacters(in: .whitespacesAndNewlines), !guid.isEmpty,
                  let track = item.trackId, track > 0 else { continue }
            if let showID, let collection = item.collectionId, collection != showID { continue }
            map[guid] = track
        }
        return map
    }

    /// The exact episode when its GUID is known, otherwise the show page.
    public static func link(forGUID guid: String, in map: [String: Int], show: ShowInfo = .mrt) -> (url: URL, isExactEpisode: Bool)? {
        if let track = map[guid], let url = episodeURL(trackID: track, show: show) { return (url, true) }
        if let url = PodcastLinks.appleShow(show: show) { return (url, false) }
        return nil
    }
}

extension PodcastLinks {
    /// Overcast resolves a show from its iTunes id.
    public static func overcastShow(show: ShowInfo = .mrt) -> URL? {
        guard let id = show.applePodcastID, !id.isEmpty else { return nil }
        return URL(string: "https://overcast.fm/itunes\(id)")
    }

    public static func buzzsproutShow(show: ShowInfo = .mrt) -> URL? {
        guard let id = show.buzzsproutShowID, !id.isEmpty else { return nil }
        return URL(string: "https://www.buzzsprout.com/\(id)")
    }
}

// MARK: - Follow the Show

/// The show's official places, in the order Settings lists them. Every link was
/// verified (Oct 10 2026); YouTube was supplied by Walter.
public struct FollowLink: Hashable, Sendable, Identifiable {
    public var id: String { title }
    public let title: String
    public let url: URL
    public let symbol: String
    public let tileHex: String
}

public enum FollowTheShow {
    public static func links(show: ShowInfo = .mrt) -> [FollowLink] {
        var out: [FollowLink] = []
        func add(_ title: String, _ url: URL?, _ symbol: String, _ hex: String) {
            if let url { out.append(FollowLink(title: title, url: url, symbol: symbol, tileHex: hex)) }
        }
        add("Apple Podcasts", PodcastLinks.appleShow(show: show), "apple.logo", "#9B4DE0")
        add("Spotify", PodcastLinks.spotifyShow(show: show), "waveform", "#1DB954")
        add("Overcast", PodcastLinks.overcastShow(show: show), "dot.radiowaves.left.and.right", "#FC7E0F")
        add("Buzzsprout (podcast page)", PodcastLinks.buzzsproutShow(show: show), "globe", "#3A9CA6")
        add("YouTube  @theMrtPodcast", URL(string: "https://www.youtube.com/@theMrtPodcast"), "play.rectangle.fill", "#FF0000")
        add("Instagram  @themrtpodcast", URL(string: "https://www.instagram.com/themrtpodcast"), "camera", "#C13584")
        add("X  @TheMRTPodcast", URL(string: "https://x.com/TheMRTPodcast"), "at", "#3C3C43")
        add("Facebook", URL(string: "https://www.facebook.com/people/The-Movie-Roulette-Tuesday-Podcast/100092512094792/"), "person.2", "#1877F2")
        return out
    }
}

// MARK: - Suggest a movie

/// The pre-filled email for "Suggest a movie". Nothing is sent by the app:
/// Mail (or the user's mail app) sends it only when the user taps Send.
public struct MovieSuggestion: Equatable, Sendable {
    public static let address = "theMrtPodcast@gmail.com"

    public var title: String
    public var why: String
    /// nil or empty = no category.
    public var category: String?
    /// Optional "credit me as" name, on its own `From:` line. nil or empty = none.
    public var credit: String?

    public init(title: String, why: String = "", category: String? = nil, credit: String? = nil) {
        self.title = title
        self.why = why
        self.category = category
        self.credit = credit
    }

    private static func clean(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var trimmedTitle: String { Self.clean(title) }
    public var isValid: Bool { !trimmedTitle.isEmpty }

    public var subject: String { "Movie suggestion: \(trimmedTitle)" }

    public var body: String {
        var lines = ["Hi MRT Crew,", "", "I’d love to hear you cover:", "", "Movie: \(trimmedTitle)"]
        let why = Self.clean(why)
        if !why.isEmpty { lines.append("Why: \(why)") }
        if let credit, !Self.clean(credit).isEmpty { lines.append("From: \(Self.clean(credit))") }
        if let category, !Self.clean(category).isEmpty { lines.append("Category: \(Self.clean(category))") }
        lines += ["", "Thanks for the show!", "", "Sent from the Movie Roulette Tuesday app"]
        return lines.joined(separator: "\n")
    }

    /// `mailto:` fallback (when Mail's compose sheet isn't available).
    public var mailtoURL: URL? {
        var comps = URLComponents()
        comps.scheme = "mailto"
        comps.path = Self.address
        comps.queryItems = [URLQueryItem(name: "subject", value: subject), URLQueryItem(name: "body", value: body)]
        // URLComponents leaves "+" alone; mail clients read it literally, but
        // encode it anyway so "A+B" titles survive every client.
        comps.percentEncodedQuery = comps.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return comps.url
    }
}

// MARK: - In-app suggestion (CloudKit backup to email)

/// A suggestion sent from the in-app form as a `Suggestion` record in the
/// CloudKit public database (create-only for listeners). Email stays the
/// default; this is the backup when email isn't available.
public struct InAppSuggestion: Equatable, Sendable {
    public static let recordType = "Suggestion"
    public static let titleLimit = 120
    public static let noteLimit = 280
    public static let nameLimit = 60

    public enum Problem: Equatable, Sendable {
        case missingTitle, titleTooLong, noteTooLong, nameTooLong
    }

    public var title: String
    /// nil or empty = no category.
    public var category: String?
    public var note: String
    /// Optional "credit me as".
    public var creditName: String

    public init(title: String, category: String? = nil, note: String = "", creditName: String = "") {
        self.title = title
        self.category = category
        self.note = note
        self.creditName = creditName
    }

    private static func clean(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var trimmedTitle: String { Self.clean(title) }
    public var trimmedNote: String { Self.clean(note) }
    public var trimmedCreditName: String { Self.clean(creditName) }
    public var trimmedCategory: String? { category.map(Self.clean).flatMap { $0.isEmpty ? nil : $0 } }

    public var problems: [Problem] {
        var out: [Problem] = []
        if trimmedTitle.isEmpty { out.append(.missingTitle) }
        if trimmedTitle.count > Self.titleLimit { out.append(.titleTooLong) }
        if trimmedNote.count > Self.noteLimit { out.append(.noteTooLong) }
        if trimmedCreditName.count > Self.nameLimit { out.append(.nameTooLong) }
        return out
    }

    public var isValid: Bool { problems.isEmpty }

    /// Characters left for the note (negative when over).
    public var noteCharactersLeft: Int { Self.noteLimit - trimmedNote.count }

    /// Typing guard for the text fields: never longer than `limit` characters.
    public static func capped(_ text: String, to limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit)) : text
    }

    /// The same pick as an email (for the mail fallbacks).
    /// The credit is its own `From:` line (never folded into `Why:`), so an
    /// empty note gives no `Why:` line at all.
    public var asEmail: MovieSuggestion {
        MovieSuggestion(title: title, why: trimmedNote, category: trimmedCategory,
                        credit: trimmedCreditName.isEmpty ? nil : trimmedCreditName)
    }
}

/// Local spam guard: one in-app suggestion per `interval` on this device.
public struct SuggestionRateLimit: Equatable, Sendable {
    public static let interval: TimeInterval = 600
    public static let defaultsKey = "suggestions.lastSentAt"

    public var lastSent: Date?
    public var interval: TimeInterval

    public init(lastSent: Date? = nil, interval: TimeInterval = SuggestionRateLimit.interval) {
        self.lastSent = lastSent
        self.interval = interval
    }

    /// Whole seconds until the next send is allowed, or nil when allowed now.
    /// A clock that moved backwards never blocks for longer than `interval`.
    public func secondsRemaining(now: Date = Date()) -> Int? {
        guard let lastSent else { return nil }
        let elapsed = now.timeIntervalSince(lastSent)
        if elapsed < 0 { return nil }
        guard elapsed < interval else { return nil }
        return max(1, Int((interval - elapsed).rounded(.up)))
    }

    public func canSend(now: Date = Date()) -> Bool { secondsRemaining(now: now) == nil }

    public mutating func recordSend(now: Date = Date()) { lastSent = now }

    public static func load(from defaults: UserDefaults) -> SuggestionRateLimit {
        SuggestionRateLimit(lastSent: defaults.object(forKey: defaultsKey) as? Date)
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(lastSent, forKey: Self.defaultsKey)
    }

    /// "Try again in 7 min."
    public static func message(seconds: Int) -> String {
        let minutes = max(1, Int((Double(seconds) / 60).rounded(.up)))
        return "You just sent one. Try again in \(minutes) min."
    }
}

// MARK: - New-episode alerts

/// What the background check remembers between runs (stored locally).
public struct NewEpisodeWatermark: Codable, Equatable, Sendable {
    public var latestDate: Date?
    public var seenGUIDs: [String]

    public init(latestDate: Date? = nil, seenGUIDs: [String] = []) {
        self.latestDate = latestDate
        self.seenGUIDs = seenGUIDs
    }

    /// Keeps the check small: only the newest GUIDs matter.
    public static let guidLimit = 50
}

public enum NewEpisodeDiff {
    /// Baseline from the current feed: nothing in it is "new".
    public static func watermark(for episodes: [PodcastEpisode]) -> NewEpisodeWatermark {
        let sorted = episodes.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
        return NewEpisodeWatermark(
            latestDate: sorted.compactMap(\.pubDate).first,
            seenGUIDs: Array(sorted.prefix(NewEpisodeWatermark.guidLimit).map(\.guid))
        )
    }

    /// Episodes published after the watermark that it hasn't seen, newest first.
    /// With no watermark yet (first run) nothing is new: the caller stores the
    /// baseline instead of alerting about the whole back catalog.
    public static func newEpisodes(in episodes: [PodcastEpisode], since mark: NewEpisodeWatermark?) -> [PodcastEpisode] {
        guard let mark else { return [] }
        let seen = Set(mark.seenGUIDs)
        return episodes
            .filter { ep in
                guard !seen.contains(ep.guid) else { return false }
                guard let latest = mark.latestDate else { return true }
                guard let date = ep.pubDate else { return false }
                return date > latest
            }
            .sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
    }

    /// Notification text for one or several new episodes.
    public static func notificationText(for new: [PodcastEpisode]) -> (title: String, body: String)? {
        guard let first = new.first else { return nil }
        if new.count == 1 {
            return ("New episode of Movie Roulette Tuesday", first.title)
        }
        return ("\(new.count) new episodes of Movie Roulette Tuesday", "Latest: \(first.title)")
    }
}
