import Foundation
import Observation
import MRTCore
import MRTShared

/// App-side state for anonymous polls + listener ratings. Talks to any
/// `CommunityStore` (CloudKit in the app, in-memory in previews), keeps a
/// small local cache of what *this device* submitted, and caches fetched
/// results briefly so tab switches don't hit iCloud every time.
@MainActor
@Observable
final class CommunityService {
    private struct LocalSubmission<V: Codable>: Codable {
        var value: V
        var recordName: String
    }

    private(set) var accountStatus: CommunityAccountStatus = .unknown
    private(set) var pollResults: [String: PollResults] = [:]
    private(set) var ratingAggregates: [String: RatingAggregate] = [:]
    /// Keys currently loading/submitting (poll ids or movie ids).
    private(set) var busy: Set<String> = []
    /// Last error per poll id / movie id.
    private(set) var errors: [String: String] = [:]

    /// Local "votedPolls" cache: pollId -> option id (+ record name).
    private var votedPolls: [String: LocalSubmission<String>] = [:]
    /// movieId -> half-stars (1...10) this device submitted to the listener average.
    private var listenerRatings: [String: LocalSubmission<Int>] = [:]

    let pollOverrides: PollOverrides?

    private let store: any CommunityStore
    private let defaults: UserDefaults
    @ObservationIgnored private var pollCache = TimedCache<String, [String: String]>(ttl: 60)
    @ObservationIgnored private var ratingCache = TimedCache<String, [String: Int]>(ttl: 60)
    @ObservationIgnored private var lastAccountCheck: Date?
    /// Set after rate limiting / quota errors; while active, cached results
    /// are shown instead of calling the service (no retry loops).
    @ObservationIgnored private var backoff = CommunityBackoff()

    private static let votedPollsKey = "community.votedPolls"
    /// Whole stars (before half-stars); migrated once to `listenerHalfStarsKey`.
    private static let listenerRatingsKey = "community.listenerRatings"
    private static let listenerHalfStarsKey = "community.listenerHalfStars"

    init(store: any CommunityStore, defaults: UserDefaults = .standard, bundle: Bundle = .main) {
        self.store = store
        self.defaults = defaults
        self.pollOverrides = bundle.url(forResource: "polls", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? PollOverrides.decode($0) }
        votedPolls = Self.load(Self.votedPollsKey, from: defaults) ?? [:]
        if let half: [String: LocalSubmission<Int>] = Self.load(Self.listenerHalfStarsKey, from: defaults) {
            listenerRatings = half
        } else {
            let legacy: [String: LocalSubmission<Int>] = Self.load(Self.listenerRatingsKey, from: defaults) ?? [:]
            listenerRatings = legacy.compactMapValues { sub in
                HalfStars.fromLegacyStars(sub.value).map { LocalSubmission(value: $0, recordName: sub.recordName) }
            }
            if !legacy.isEmpty { save(listenerRatings, Self.listenerHalfStarsKey) }
        }
    }

    // MARK: Account

    func refreshAccountStatus(force: Bool = false) async {
        if !force, let last = lastAccountCheck, Date().timeIntervalSince(last) < 30, accountStatus != .unknown { return }
        lastAccountCheck = Date()
        accountStatus = await store.accountStatus()
    }

    var accountMessage: String? {
        switch accountStatus {
        case .unknown, .available: return nil
        case .noAccount: return "Sign in to iCloud in Settings to vote or rate."
        case .unavailable(let message): return message
        }
    }

    // MARK: Polls

    func poll(forEpisode guid: String, show: ShowInfo) -> PollDefinition {
        PollFactory.poll(forEpisode: guid, hosts: show.hosts, overrides: pollOverrides)
    }

    func myVote(for poll: PollDefinition) -> String? { votedPolls[poll.id]?.value }

    /// Results are shown after voting, or to people who can't vote (not
    /// signed in), so they still see how listeners voted.
    func canSeeResults(_ poll: PollDefinition) -> Bool {
        if myVote(for: poll) != nil { return true }
        switch accountStatus {
        case .noAccount, .unavailable: return true
        case .available, .unknown: return false
        }
    }

    func loadPoll(_ poll: PollDefinition, force: Bool = false) async {
        await refreshAccountStatus()
        // Reinstalled / new device: recover this user's vote from iCloud.
        if accountStatus.canWrite, votedPolls[poll.id] == nil,
           let option = try? await store.myVote(pollId: poll.id) {
            votedPolls[poll.id] = LocalSubmission(
                value: option, recordName: ""  // name unknown here; merge isn't needed for an indexed vote
            )
            save(votedPolls, Self.votedPollsKey)
        }
        guard canSeeResults(poll) else { return }
        await fetchPollResults(poll, force: force)
    }

    func vote(_ poll: PollDefinition, option: PollOption) async {
        guard poll.options.contains(option), !busy.contains(poll.id) else { return }
        if let blocked = backoffMessage() { errors[poll.id] = blocked; return }
        busy.insert(poll.id)
        defer { busy.remove(poll.id) }
        await refreshAccountStatus()
        guard accountStatus.canWrite else {
            errors[poll.id] = accountMessage ?? CommunityError.notSignedIn.localizedDescription
            return
        }
        do {
            let name = try await store.submitVote(pollId: poll.id, option: option.id)
            votedPolls[poll.id] = LocalSubmission(value: option.id, recordName: name)
            save(votedPolls, Self.votedPollsKey)
            errors[poll.id] = nil
            pollCache.invalidate(poll.id)
            await fetchPollResults(poll, force: true)
        } catch {
            guard let message = handle(error) else { return }
            errors[poll.id] = message
        }
    }

    private func fetchPollResults(_ poll: PollDefinition, force: Bool) async {
        if !force, let cached = pollCache.value(for: poll.id) {
            publish(poll, votes: cached)
            return
        }
        if let blocked = backoffMessage() {
            errors[poll.id] = blocked
            if let stale = pollCache.staleValue(for: poll.id) { publish(poll, votes: stale) }
            return
        }
        busy.insert(poll.id)
        defer { busy.remove(poll.id) }
        do {
            let votes = try await store.fetchVotes(pollId: poll.id)
            pollCache.insert(votes, for: poll.id)
            errors[poll.id] = nil
            publish(poll, votes: votes)
        } catch {
            guard let message = handle(error) else { return }
            errors[poll.id] = message
            if let stale = pollCache.staleValue(for: poll.id) { publish(poll, votes: stale) }
        }
    }

    private func publish(_ poll: PollDefinition, votes: [String: String]) {
        let merged = CommunityMerge.merging(votes, own: Self.own(votedPolls[poll.id]))
        pollResults[poll.id] = PollResults.tally(poll: poll, votes: merged.values)
    }

    // MARK: Listener ratings

    /// Half-stars this device shared for the movie.
    func myListenerRating(movieId: String) -> Int? { listenerRatings[movieId]?.value }

    func loadRating(movieId: String, force: Bool = false) async {
        await refreshAccountStatus()
        if accountStatus.canWrite, listenerRatings[movieId] == nil,
           let half = try? await store.myRating(movieId: movieId) {
            listenerRatings[movieId] = LocalSubmission(value: half, recordName: "")
            save(listenerRatings, Self.listenerHalfStarsKey)
        }
        if !force, let cached = ratingCache.value(for: movieId) {
            publishRating(movieId, ratings: cached)
            return
        }
        if let blocked = backoffMessage() {
            errors[movieId] = blocked
            if let stale = ratingCache.staleValue(for: movieId) { publishRating(movieId, ratings: stale) }
            return
        }
        busy.insert(movieId)
        defer { busy.remove(movieId) }
        do {
            let ratings = try await store.fetchRatings(movieId: movieId)
            ratingCache.insert(ratings, for: movieId)
            errors[movieId] = nil
            publishRating(movieId, ratings: ratings)
        } catch {
            guard let message = handle(error) else { return }
            errors[movieId] = message
            if let stale = ratingCache.staleValue(for: movieId) { publishRating(movieId, ratings: stale) }
        }
    }

    func submitListenerRating(movieId: String, halfStars: Int) async {
        guard HalfStars.range.contains(halfStars), !busy.contains(movieId) else { return }
        if let blocked = backoffMessage() { errors[movieId] = blocked; return }
        busy.insert(movieId)
        await refreshAccountStatus()
        guard accountStatus.canWrite else {
            busy.remove(movieId)
            errors[movieId] = accountMessage ?? CommunityError.notSignedIn.localizedDescription
            return
        }
        defer { busy.remove(movieId) }
        do {
            let name = try await store.submitRating(movieId: movieId, halfStars: halfStars)
            listenerRatings[movieId] = LocalSubmission(value: halfStars, recordName: name)
            save(listenerRatings, Self.listenerHalfStarsKey)
            errors[movieId] = nil
            ratingCache.invalidate(movieId)
        } catch {
            if let message = handle(error) { errors[movieId] = message }
            return
        }
        await loadRating(movieId: movieId, force: true)
    }

    private func publishRating(_ movieId: String, ratings: [String: Int]) {
        let merged = CommunityMerge.merging(ratings, own: Self.own(listenerRatings[movieId]))
        ratingAggregates[movieId] = RatingAggregate.from(halfStars: merged.values)
    }

    // MARK: Suggestions (in-app backup to email)

    /// Saves the suggestion to iCloud. Returns nil on success, else a friendly
    /// message (the form then offers the email fallbacks).
    func submitSuggestion(_ suggestion: InAppSuggestion) async -> String? {
        guard suggestion.isValid else { return "Add a movie title (note up to \(InAppSuggestion.noteLimit) characters)." }
        await refreshAccountStatus(force: true)
        guard accountStatus.canWrite else {
            return "iCloud isn’t available. Sign in to iCloud in Settings, or use email instead."
        }
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
            + " (" + (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?") + ")"
        do {
            try await store.submitSuggestion(suggestion, appVersion: version)
            return nil
        } catch {
            if error is CancellationError { return "Cancelled." }
            if (error as? CommunityError) == .notSignedIn { accountStatus = .noAccount }
            return (error as? LocalizedError)?.errorDescription ?? "Couldn’t send. Try email instead."
        }
    }

    /// Friendly message for an error, or nil when it should be ignored
    /// (cancelled because the screen went away). Also updates sign-in state
    /// and the back-off window.
    private func handle(_ error: Error) -> String? {
        if error is CancellationError { return nil }
        if let url = error as? URLError, url.code == .cancelled { return nil }
        if (error as? CommunityError) == .notSignedIn { accountStatus = .noAccount }
        backoff.note(error)
        return (error as? LocalizedError)?.errorDescription ?? "Something went wrong. Try again later."
    }

    private func backoffMessage() -> String? {
        guard let seconds = backoff.secondsRemaining() else { return nil }
        return CommunityError.busy(retryAfter: seconds).localizedDescription
    }

    /// This device's own record, when we know its name (i.e. we saved it this install).
    private static func own<V: Codable>(_ submission: LocalSubmission<V>?) -> (recordName: String, value: V)? {
        guard let submission, !submission.recordName.isEmpty else { return nil }
        return (recordName: submission.recordName, value: submission.value)
    }

    // MARK: Local persistence (UserDefaults; tiny)

    private static func load<T: Decodable>(_ key: String, from defaults: UserDefaults) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}

extension CommunityService {
    /// CloudKit in the app. In-memory when running SwiftUI previews or when
    /// launched with `-MRTMockCommunity` (Scheme > Run > Arguments), so the app
    /// runs without iCloud.
    static func makeDefault() -> CommunityService {
        let info = ProcessInfo.processInfo
        if info.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" || info.arguments.contains("-MRTMockCommunity") {
            return preview()
        }
        return CommunityService(store: CloudKitCommunityStore())
    }

    /// In-memory store seeded with a few fake listeners (previews/simulator).
    static func preview(signedIn: Bool = true) -> CommunityService {
        CommunityService(
            store: InMemoryCommunityStore(currentUser: signedIn ? "preview-user" : nil),
            defaults: UserDefaults(suiteName: "mrt-preview-community") ?? .standard
        )
    }
}
