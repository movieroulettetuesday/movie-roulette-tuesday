import Foundation

// MARK: - Record names (one record per user per poll / movie, no identity stored)

/// Deterministic CloudKit record names. The same iCloud user voting again on
/// the same poll produces the same record name, so the save overwrites their
/// previous vote instead of adding a duplicate. Only a SHA-256 of
/// (user record name + id) appears in the name; the raw user record ID is
/// never written to any record field.
public enum CommunityRecordNames {
    public static let voteRecordType = "PollVote"
    public static let ratingRecordType = "ListenerRating"

    /// `vote-<pollId>-<sha256(userRecordName + pollId)>`
    public static func vote(pollId: String, userRecordName: String) -> String {
        "vote-\(safeComponent(pollId))-\(SHA256Digest.hex(userRecordName + pollId))"
    }

    /// `rating-<movieId>-<sha256(userRecordName + "rating:" + movieId)>`
    public static func rating(movieId: String, userRecordName: String) -> String {
        "rating-\(safeComponent(movieId))-\(SHA256Digest.hex(userRecordName + "rating:" + movieId))"
    }

    /// CloudKit record names must be ASCII, not start with "_", and be at most
    /// 255 chars. Ids made of [A-Za-z0-9._-] (all of ours) pass through; anything
    /// else (or anything long) is replaced by a short hash so names stay valid.
    public static func safeComponent(_ id: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        if !id.isEmpty, id.count <= 120, id.allSatisfy(allowed.contains) { return id }
        return "h" + String(SHA256Digest.hex(id).prefix(32))
    }
}

// MARK: - Polls

public struct PollOption: Codable, Hashable, Identifiable, Sendable {
    /// Stored in `PollVote.option`. Keep stable once people have voted.
    public var id: String
    public var label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

public struct PollDefinition: Codable, Hashable, Identifiable, Sendable {
    /// Stored in `PollVote.pollId`.
    public var id: String
    public var episodeGuid: String
    public var question: String
    public var options: [PollOption]

    public init(id: String, episodeGuid: String, question: String, options: [PollOption]) {
        self.id = id
        self.episodeGuid = episodeGuid
        self.question = question
        self.options = options
    }
}

/// Optional bundled `polls.json`: per-episode overrides of the default poll.
///
///     { "polls": [ { "episodeGuid": "Buzzsprout-123", "question": "…",
///                    "options": ["Yes", "No"], "id": "optional-stable-id" } ] }
public struct PollOverrides: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var episodeGuid: String
        public var question: String
        public var options: [String]
        public var id: String?

        public init(episodeGuid: String, question: String, options: [String], id: String? = nil) {
            self.episodeGuid = episodeGuid
            self.question = question
            self.options = options
            self.id = id
        }
    }

    public var polls: [Entry]

    public init(polls: [Entry] = []) { self.polls = polls }

    public static func decode(_ data: Data) throws -> PollOverrides {
        try JSONDecoder().decode(PollOverrides.self, from: data)
    }

    public func entry(forEpisode guid: String) -> Entry? {
        polls.first { $0.episodeGuid == guid && $0.options.count >= 2 && !$0.question.isEmpty }
    }
}

/// Client-side poll definitions: no admin backend, so every episode gets one
/// deterministic default poll unless `polls.json` overrides it.
public enum PollFactory {
    public enum Kind: String, CaseIterable, Sendable {
        case goodOrBad, recommend, argument
    }

    /// Same episode -> same poll kind on every device (FNV-1a, not `Hasher`).
    public static func defaultKind(forEpisode guid: String) -> Kind {
        let all = Kind.allCases
        return all[Int(SpinOfTheDay.stableHash("poll:" + guid) % UInt64(all.count))]
    }

    public static func defaultPoll(forEpisode guid: String, hosts: [String]) -> PollDefinition {
        let kind = defaultKind(forEpisode: guid)
        let base = CommunityRecordNames.safeComponent(guid)
        switch kind {
        case .goodOrBad:
            return PollDefinition(
                id: "\(base).good-bad", episodeGuid: guid, question: "Was this movie good or bad?",
                options: [PollOption(id: "good", label: "Good"), PollOption(id: "bad", label: "Bad")]
            )
        case .recommend:
            return PollDefinition(
                id: "\(base).recommend", episodeGuid: guid, question: "Would you recommend it?",
                options: [PollOption(id: "yes", label: "Yes"), PollOption(id: "no", label: "No")]
            )
        case .argument:
            let names = hosts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let hostOptions: [PollOption] = names.count >= 2
                ? names.enumerated().map { PollOption(id: "host-\($0.offset + 1)", label: $0.element) }
                : [PollOption(id: "host-1", label: "Host A"), PollOption(id: "host-2", label: "Host B")]
            return PollDefinition(
                id: "\(base).argument", episodeGuid: guid, question: "Who won the argument?",
                options: hostOptions + [PollOption(id: "tie", label: "Tie")]
            )
        }
    }

    public static func poll(forEpisode guid: String, hosts: [String], overrides: PollOverrides?) -> PollDefinition {
        guard let entry = overrides?.entry(forEpisode: guid) else {
            return defaultPoll(forEpisode: guid, hosts: hosts)
        }
        let id = entry.id.map(CommunityRecordNames.safeComponent)
            ?? "\(CommunityRecordNames.safeComponent(guid)).custom-\(SHA256Digest.hex(entry.question).prefix(8))"
        let options = entry.options.enumerated().map { PollOption(id: "opt-\($0.offset + 1)", label: $0.element) }
        return PollDefinition(id: id, episodeGuid: guid, question: entry.question, options: options)
    }
}

// MARK: - Aggregation (pure; counted client-side from fetched records)

public struct PollResults: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        public var option: PollOption
        public var count: Int
        /// 0...1 (0 when there are no votes).
        public var fraction: Double
    }

    public var pollId: String
    public var rows: [Row]
    public var total: Int

    /// Options in poll order; votes for unknown options (e.g. an edited poll) are ignored.
    public static func tally<S: Sequence>(poll: PollDefinition, votes: S) -> PollResults where S.Element == String {
        let valid = Set(poll.options.map(\.id))
        let counts = votes.filter(valid.contains).reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        let total = counts.values.reduce(0, +)
        let rows = poll.options.map { option -> Row in
            let n = counts[option.id, default: 0]
            return Row(option: option, count: n, fraction: total == 0 ? 0 : Double(n) / Double(total))
        }
        return PollResults(pollId: poll.id, rows: rows, total: total)
    }

    public var leaders: [PollOption] {
        guard let top = rows.map(\.count).max(), top > 0 else { return [] }
        return rows.filter { $0.count == top }.map(\.option)
    }
}

public struct RatingAggregate: Equatable, Sendable {
    public var count: Int
    /// nil when there are no valid ratings.
    public var average: Double?
    /// Index 0 = 1 star ... index 4 = 5 stars.
    public var histogram: [Int]

    /// The average in stars rounded to the nearest half star (for display).
    public var averageToHalf: Double? { average.map(HalfStars.roundedToHalf) }
    /// `averageToHalf` as half-stars 1...10 (for `StarRatingView`).
    public var averageHalfStars: Int? { averageToHalf.flatMap { HalfStars.clamped(Int(($0 * 2).rounded())) } }

    /// Whole stars; values outside 1...5 are ignored.
    public static func from<S: Sequence>(stars: S) -> RatingAggregate where S.Element == Int {
        from(halfStars: stars.filter { PersonalRatings.ratingRange.contains($0) }.map { $0 * 2 })
    }

    /// Half-stars 1...10 (average in stars); values outside 1...10 are ignored.
    /// The histogram counts rounded whole stars.
    public static func from<S: Sequence>(halfStars: S) -> RatingAggregate where S.Element == Int {
        let valid = halfStars.filter { HalfStars.range.contains($0) }
        var histogram = [Int](repeating: 0, count: 5)
        for h in valid { histogram[HalfStars.roundedStars(h) - 1] += 1 }
        return RatingAggregate(
            count: valid.count,
            average: valid.isEmpty ? nil : Double(valid.reduce(0, +)) / 2 / Double(valid.count),
            histogram: histogram
        )
    }
}

/// Tiny time-boxed cache so tab switches don't refetch from CloudKit every time.
public struct TimedCache<Key: Hashable, Value> {
    public var ttl: TimeInterval
    /// Hard cap on entries; the oldest entry is evicted first.
    public var maxEntries: Int
    private var storage: [Key: (value: Value, storedAt: Date)] = [:]

    public init(ttl: TimeInterval, maxEntries: Int = 200) {
        self.ttl = ttl
        self.maxEntries = max(1, maxEntries)
    }

    public var count: Int { storage.count }

    public func value(for key: Key, now: Date = Date()) -> Value? {
        guard let hit = storage[key], now.timeIntervalSince(hit.storedAt) < ttl else { return nil }
        return hit.value
    }

    /// Ignores freshness; for showing stale data while refreshing.
    public func staleValue(for key: Key) -> Value? { storage[key]?.value }

    public mutating func insert(_ value: Value, for key: Key, now: Date = Date()) {
        storage[key] = (value, now)
        while storage.count > maxEntries,
              let oldest = storage.min(by: { $0.value.storedAt < $1.value.storedAt })?.key {
            storage[oldest] = nil
        }
    }

    public mutating func invalidate(_ key: Key) { storage[key] = nil }
}

// MARK: - Store abstraction

public enum CommunityAccountStatus: Equatable, Sendable {
    case unknown
    /// Signed into iCloud: can vote and rate.
    case available
    /// Not signed in (or restricted): can still read results.
    case noAccount
    case unavailable(String)

    public var canWrite: Bool { self == .available }
}

public enum CommunityError: Error, Equatable, LocalizedError, Sendable {
    case notSignedIn
    case invalidOption
    case invalidStars
    /// No network (CloudKit networkUnavailable / networkFailure).
    case offline
    /// Rate limited / zone busy / service unavailable. `retryAfter` in seconds when CloudKit gives one.
    case busy(retryAfter: Int?)
    /// The public database is over quota.
    case quotaExceeded
    /// Schema or container not set up (e.g. schema not deployed to Production).
    case notSetUp
    case service(String)

    public var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Sign in to iCloud in Settings to vote or rate."
        case .invalidOption: return "Something went wrong with that vote. Try again."
        case .invalidStars: return "Ratings are ½ to 5 stars."
        case .offline: return "You’re offline. Listener results will load when you’re back online."
        case .busy(let seconds?) where seconds > 0:
            return "iCloud is busy right now. Try again in \(seconds) second\(seconds == 1 ? "" : "s")."
        case .busy: return "iCloud is busy right now. Try again in a moment."
        case .quotaExceeded: return "Listener features are temporarily unavailable. Please try again later."
        case .notSetUp: return "Listener polls and ratings aren’t available yet. Check back later."
        case .service(let message): return message
        }
    }

    /// Minimum wait before talking to the service again after this error.
    public var backoffSeconds: TimeInterval? {
        switch self {
        case .busy(let seconds): return TimeInterval(min(max(seconds ?? 10, 1), 300))
        case .quotaExceeded: return 60
        default: return nil
        }
    }
}

/// Client-side back-off after rate limiting: while blocked, the app shows
/// cached results instead of calling CloudKit. Nothing ever retries in a loop;
/// requests only happen when the user opens a screen or taps.
public struct CommunityBackoff: Sendable, Equatable {
    public private(set) var blockedUntil: Date?

    public init() {}

    public mutating func note(_ error: Error, now: Date = Date()) {
        guard let seconds = (error as? CommunityError)?.backoffSeconds else { return }
        let until = now.addingTimeInterval(seconds)
        if let blockedUntil, blockedUntil > until { return }
        blockedUntil = until
    }

    public func isBlocked(now: Date = Date()) -> Bool {
        guard let blockedUntil else { return false }
        return now < blockedUntil
    }

    /// Whole seconds left (rounded up), or nil when not blocked.
    public func secondsRemaining(now: Date = Date()) -> Int? {
        guard let blockedUntil, now < blockedUntil else { return nil }
        return Int(blockedUntil.timeIntervalSince(now).rounded(.up))
    }

    public mutating func reset() { blockedUntil = nil }
}

/// Anonymous community data (poll votes + listener ratings). The app uses a
/// CloudKit public-database implementation; previews, the simulator without
/// iCloud, and tests use `InMemoryCommunityStore`.
public protocol CommunityStore: Sendable {
    func accountStatus() async -> CommunityAccountStatus
    /// Creates or overwrites this user's single vote for `pollId`. Returns the record name.
    @discardableResult
    func submitVote(pollId: String, option: String) async throws -> String
    /// recordName -> option for every vote on the poll (one per voter).
    /// Readable without iCloud sign-in.
    func fetchVotes(pollId: String) async throws -> [String: String]
    /// This user's vote, if signed in and they've voted.
    func myVote(pollId: String) async throws -> String?
    /// Creates or overwrites this user's single rating for `movieId` (half-stars
    /// 1...10; the legacy `stars` field gets the rounded value). Returns the record name.
    @discardableResult
    func submitRating(movieId: String, halfStars: Int) async throws -> String
    /// recordName -> half-stars for every listener rating of the movie
    /// (legacy records without `halfStars` read as stars × 2).
    func fetchRatings(movieId: String) async throws -> [String: Int]
    /// This user's rating in half-stars.
    func myRating(movieId: String) async throws -> Int?
    /// Creates one `Suggestion` record (create-only; listeners can't read them).
    func submitSuggestion(_ suggestion: InAppSuggestion, appVersion: String) async throws
}

/// Merges this device's own just-saved record into fetched results. Public-DB
/// queries are eventually consistent, so a vote saved a moment ago may be
/// missing (or show its old value); keyed by record name, it's never double-counted.
public enum CommunityMerge {
    public static func merging<V>(_ fetched: [String: V], own: (recordName: String, value: V)?) -> [String: V] {
        guard let own else { return fetched }
        var merged = fetched
        merged[own.recordName] = own.value
        return merged
    }
}

/// In-memory store with the same one-record-per-user semantics as CloudKit
/// (records keyed by the deterministic record name).
public actor InMemoryCommunityStore: CommunityStore {
    public struct VoteRecord: Equatable, Sendable { public var pollId: String; public var option: String }
    public struct RatingRecord: Equatable, Sendable {
        public var movieId: String
        /// Legacy whole stars (always written).
        public var stars: Int
        /// nil = a record from an older build.
        public var halfStars: Int?
        public var resolvedHalfStars: Int? { HalfStars.resolved(halfStars: halfStars, legacyStars: stars) }
    }

    private var votes: [String: VoteRecord] = [:]
    private var ratings: [String: RatingRecord] = [:]
    private var currentUser: String?
    public private(set) var suggestions: [InAppSuggestion] = []

    /// `currentUser == nil` behaves like "not signed into iCloud".
    public init(currentUser: String? = "preview-user") {
        self.currentUser = currentUser
    }

    public func setCurrentUser(_ user: String?) { currentUser = user }
    public var voteRecordNames: [String] { votes.keys.sorted() }
    public var ratingRecordNames: [String] { ratings.keys.sorted() }

    /// Seed data for previews (other listeners).
    public func seedVotes(pollId: String, options: [String]) {
        for (i, option) in options.enumerated() {
            votes[CommunityRecordNames.vote(pollId: pollId, userRecordName: "seed-\(i)")] = VoteRecord(pollId: pollId, option: option)
        }
    }

    public func seedRatings(movieId: String, stars: [Int]) {
        for (i, s) in stars.enumerated() {
            ratings[CommunityRecordNames.rating(movieId: movieId, userRecordName: "seed-\(i)")] = RatingRecord(movieId: movieId, stars: s, halfStars: nil)
        }
    }

    /// Seeds half-star records written by new builds.
    public func seedHalfStarRatings(movieId: String, halfStars: [Int]) {
        for (i, h) in halfStars.enumerated() {
            ratings[CommunityRecordNames.rating(movieId: movieId, userRecordName: "seed-half-\(i)")] =
                RatingRecord(movieId: movieId, stars: HalfStars.roundedStars(h), halfStars: h)
        }
    }

    public func record(named name: String) -> RatingRecord? { ratings[name] }

    public func accountStatus() async -> CommunityAccountStatus {
        currentUser == nil ? .noAccount : .available
    }

    @discardableResult
    public func submitVote(pollId: String, option: String) async throws -> String {
        guard let user = currentUser else { throw CommunityError.notSignedIn }
        let name = CommunityRecordNames.vote(pollId: pollId, userRecordName: user)
        votes[name] = VoteRecord(pollId: pollId, option: option)
        return name
    }

    public func fetchVotes(pollId: String) async throws -> [String: String] {
        votes.filter { $0.value.pollId == pollId }.mapValues(\.option)
    }

    public func myVote(pollId: String) async throws -> String? {
        guard let user = currentUser else { return nil }
        return votes[CommunityRecordNames.vote(pollId: pollId, userRecordName: user)]?.option
    }

    @discardableResult
    public func submitRating(movieId: String, halfStars: Int) async throws -> String {
        guard let user = currentUser else { throw CommunityError.notSignedIn }
        guard HalfStars.range.contains(halfStars) else { throw CommunityError.invalidStars }
        let name = CommunityRecordNames.rating(movieId: movieId, userRecordName: user)
        ratings[name] = RatingRecord(movieId: movieId, stars: HalfStars.roundedStars(halfStars), halfStars: halfStars)
        return name
    }

    public func fetchRatings(movieId: String) async throws -> [String: Int] {
        ratings.filter { $0.value.movieId == movieId }.compactMapValues(\.resolvedHalfStars)
    }

    public func submitSuggestion(_ suggestion: InAppSuggestion, appVersion: String) async throws {
        guard currentUser != nil else { throw CommunityError.notSignedIn }
        suggestions.append(suggestion)
    }

    public func myRating(movieId: String) async throws -> Int? {
        guard let user = currentUser else { return nil }
        return ratings[CommunityRecordNames.rating(movieId: movieId, userRecordName: user)]?.resolvedHalfStars
    }
}
