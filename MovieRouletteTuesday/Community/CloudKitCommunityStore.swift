import CloudKit
import Foundation
import MRTCore
import MRTShared

/// `CommunityStore` backed by the CloudKit PUBLIC database of
/// iCloud.com.movieroulettetuesday.app.
///
/// Privacy: records hold only `pollId`/`option` or `movieId`/`stars`/`halfStars`. The
/// iCloud user record ID is used solely as hash input for the deterministic
/// record name (one vote per user per poll); it is never written to a field.
/// Reading works without iCloud sign-in; writing requires it.
///
/// Requires the schema in CloudKit/MovieRouletteTuesday.ckdb (pollId and
/// movieId QUERYABLE) to be deployed to Production before release.
actor CloudKitCommunityStore: CommunityStore {
    static let containerIdentifier = "iCloud.com.movieroulettetuesday.app"
    /// Cap on records read per poll/movie (pages of 200). Plenty for a podcast audience.
    static let maxRecords = 2_000
    static let pageSize = 200
    /// Per-request / whole-operation timeouts (CloudKit's defaults are much longer).
    static let requestTimeout: TimeInterval = 20
    static let resourceTimeout: TimeInterval = 45

    // Created lazily so merely launching the app never touches CloudKit.
    private lazy var container = CKContainer(identifier: Self.containerIdentifier)
    private var database: CKDatabase { container.publicCloudDatabase }
    private var cachedUserRecordName: String?

    private static func configuration() -> CKOperation.Configuration {
        let config = CKOperation.Configuration()
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = resourceTimeout
        config.qualityOfService = .userInitiated
        return config
    }

    func accountStatus() async -> CommunityAccountStatus {
        do {
            switch try await container.accountStatus() {
            case .available: return .available
            case .noAccount, .restricted: return .noAccount
            case .temporarilyUnavailable: return .unavailable("iCloud is temporarily unavailable. Results may still load.")
            case .couldNotDetermine: return .unavailable("iCloud isn’t available right now.")
            @unknown default: return .unavailable("iCloud isn’t available right now.")
            }
        } catch {
            let mapped = Self.communityError(for: error)
            return .unavailable((mapped as? LocalizedError)?.errorDescription ?? "iCloud isn’t available right now.")
        }
    }

    // MARK: Votes

    @discardableResult
    func submitVote(pollId: String, option: String) async throws -> String {
        let name = CommunityRecordNames.vote(pollId: pollId, userRecordName: try await userRecordName())
        try await overwrite(
            recordName: name, recordType: CommunityRecordNames.voteRecordType,
            fields: .vote(pollId: pollId, option: option)
        )
        return name
    }

    func fetchVotes(pollId: String) async throws -> [String: String] {
        let rows = try await allRecordValues(
            recordType: CommunityRecordNames.voteRecordType, field: "pollId", equals: pollId, valueKeys: ["option"]
        )
        var votes: [String: String] = [:]
        for (name, values) in rows {
            if case .string(let option)? = values["option"] { votes[name] = option }
        }
        return votes
    }

    func myVote(pollId: String) async throws -> String? {
        guard let user = try? await userRecordName() else { return nil }
        let name = CommunityRecordNames.vote(pollId: pollId, userRecordName: user)
        if case .string(let option)? = try await existingValue(recordName: name, key: "option") { return option }
        return nil
    }

    // MARK: Listener ratings

    @discardableResult
    func submitRating(movieId: String, halfStars: Int) async throws -> String {
        guard HalfStars.range.contains(halfStars) else { throw CommunityError.invalidStars }
        let name = CommunityRecordNames.rating(movieId: movieId, userRecordName: try await userRecordName())
        try await overwrite(
            recordName: name, recordType: CommunityRecordNames.ratingRecordType,
            fields: .rating(movieId: movieId, halfStars: halfStars)
        )
        return name
    }

    func fetchRatings(movieId: String) async throws -> [String: Int] {
        let rows = try await allRecordValues(
            recordType: CommunityRecordNames.ratingRecordType, field: "movieId", equals: movieId,
            valueKeys: ["halfStars", "stars"]
        )
        var ratings: [String: Int] = [:]
        for (name, values) in rows {
            if let half = Self.resolvedHalfStars(values) { ratings[name] = half }
        }
        return ratings
    }

    /// `halfStars` (new builds) or legacy `stars` × 2.
    private static func resolvedHalfStars(_ values: [String: FieldValue]) -> Int? {
        func int(_ key: String) -> Int? { if case .int(let v)? = values[key] { return v }; return nil }
        return HalfStars.resolved(halfStars: int("halfStars"), legacyStars: int("stars"))
    }

    func myRating(movieId: String) async throws -> Int? {
        guard let user = try? await userRecordName() else { return nil }
        let name = CommunityRecordNames.rating(movieId: movieId, userRecordName: user)
        let values = try await existingValues(recordName: name, keys: ["halfStars", "stars"])
        return values.flatMap(Self.resolvedHalfStars)
    }

    // MARK: Suggestions

    /// One new `Suggestion` record with a random name (never overwrites).
    func submitSuggestion(_ suggestion: InAppSuggestion, appVersion: String) async throws {
        do {
            try await database.configuredWith(configuration: Self.configuration()) { db in
                let record = CKRecord(
                    recordType: InAppSuggestion.recordType,
                    recordID: CKRecord.ID(recordName: "suggestion-\(UUID().uuidString)")
                )
                record["title"] = suggestion.trimmedTitle
                record["category"] = suggestion.trimmedCategory ?? ""
                record["note"] = suggestion.trimmedNote
                record["creditName"] = suggestion.trimmedCreditName
                record["appVersion"] = appVersion
                try await Self.save(record, in: db, policy: .ifServerRecordUnchanged)
            }
        } catch {
            throw Self.communityError(for: error)
        }
    }

    // MARK: Helpers

    /// Sendable field values pulled out of CKRecords inside CloudKit closures.
    private enum FieldValue: Sendable {
        case string(String)
        case int(Int)

        init?(_ raw: Any?) {
            if let s = raw as? String { self = .string(s) }
            else if let i = raw as? Int64 { self = .int(Int(i)) }
            else { return nil }
        }
    }

    private enum Fields: Sendable {
        case vote(pollId: String, option: String)
        case rating(movieId: String, halfStars: Int)

        func apply(to record: CKRecord) {
            switch self {
            case .vote(let pollId, let option):
                record["pollId"] = pollId
                record["option"] = option
            case .rating(let movieId, let halfStars):
                record["movieId"] = movieId
                record["halfStars"] = Int64(halfStars)
                // Rounded whole stars, so older app versions keep reading it.
                record["stars"] = Int64(HalfStars.roundedStars(halfStars))
            }
        }
    }

    /// The iCloud user's record name for this container. Only ever hashed.
    private func userRecordName() async throws -> String {
        if let cachedUserRecordName { return cachedUserRecordName }
        do {
            let name = try await container.userRecordID().recordName
            cachedUserRecordName = name
            return name
        } catch {
            throw Self.communityError(for: error)
        }
    }

    /// Save that replaces this user's previous record with the same name
    /// (`.allKeys` ignores the server change tag), so re-voting never
    /// duplicates. If the server still reports a conflict, the server's copy is
    /// updated and saved exactly once more; no loops.
    private func overwrite(recordName: String, recordType: String, fields: Fields) async throws {
        do {
            try await database.configuredWith(configuration: Self.configuration()) { db in
                let record = CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: recordName))
                fields.apply(to: record)
                do {
                    try await Self.save(record, in: db, policy: .allKeys)
                } catch let error as CKError where error.code == .serverRecordChanged {
                    guard let server = error.serverRecord else { throw error }
                    fields.apply(to: server)
                    try await Self.save(server, in: db, policy: .changedKeys)
                }
            }
        } catch {
            throw Self.communityError(for: error)
        }
    }

    private static func save(_ record: CKRecord, in db: CKDatabase, policy: CKModifyRecordsOperation.RecordSavePolicy) async throws {
        let (saveResults, _) = try await db.modifyRecords(
            saving: [record], deleting: [], savePolicy: policy, atomically: false
        )
        if let result = saveResults[record.recordID] { _ = try result.get() }
    }

    private func existingValues(recordName: String, keys: [String]) async throws -> [String: FieldValue]? {
        do {
            return try await database.configuredWith(configuration: Self.configuration()) { db in
                do {
                    let record = try await db.record(for: CKRecord.ID(recordName: recordName))
                    var out: [String: FieldValue] = [:]
                    for key in keys { if let v = FieldValue(record[key]) { out[key] = v } }
                    return out
                } catch let error as CKError where error.code == .unknownItem {
                    return nil
                }
            }
        } catch {
            throw Self.communityError(for: error)
        }
    }

    private func existingValue(recordName: String, key: String) async throws -> FieldValue? {
        do {
            return try await database.configuredWith(configuration: Self.configuration()) { db in
                do {
                    let record = try await db.record(for: CKRecord.ID(recordName: recordName))
                    return FieldValue(record[key])
                } catch let error as CKError where error.code == .unknownItem {
                    return nil
                }
            }
        } catch {
            throw Self.communityError(for: error)
        }
    }

    /// Pages through `recordType WHERE field == value` (cursor) up to
    /// `maxRecords`, returning recordName -> value. A record type that doesn't
    /// exist yet (nobody has voted/rated) means "no records".
    private func allRecordValues(
        recordType: String, field: String, equals value: String, valueKeys: [String]
    ) async throws -> [(String, [String: FieldValue])] {
        let maxRecords = Self.maxRecords
        let pageSize = Self.pageSize
        do {
            return try await database.configuredWith(configuration: Self.configuration()) { db in
                let query = CKQuery(recordType: recordType, predicate: NSPredicate(format: "%K == %@", field, value))
                var out: [(String, [String: FieldValue])] = []
                do {
                    var page = try await db.records(matching: query, desiredKeys: valueKeys, resultsLimit: pageSize)
                    while true {
                        try Task.checkCancellation()
                        for (_, result) in page.matchResults {
                            guard let record = try? result.get() else { continue }
                            var values: [String: FieldValue] = [:]
                            for key in valueKeys { if let v = FieldValue(record[key]) { values[key] = v } }
                            if !values.isEmpty { out.append((record.recordID.recordName, values)) }
                        }
                        guard let cursor = page.queryCursor, out.count < maxRecords else { break }
                        page = try await db.records(continuingMatchFrom: cursor, desiredKeys: valueKeys, resultsLimit: pageSize)
                    }
                } catch let error as CKError where error.code == .unknownItem {
                    return []
                }
                return out
            }
        } catch {
            throw Self.communityError(for: error)
        }
    }

    /// Maps CloudKit failures to friendly, non-technical `CommunityError`s.
    static func communityError(for error: Error) -> Error {
        if error is CommunityError || error is CancellationError { return error }
        guard let ck = error as? CKError else {
            if let url = error as? URLError {
                return url.code == .cancelled ? CancellationError() : CommunityError.offline
            }
            return CommunityError.service("Couldn’t reach iCloud. Try again later.")
        }
        switch ck.code {
        case .notAuthenticated:
            return CommunityError.notSignedIn
        case .networkUnavailable, .networkFailure:
            return CommunityError.offline
        case .requestRateLimited, .zoneBusy, .serviceUnavailable:
            return CommunityError.busy(retryAfter: ck.retryAfterSeconds.map { Int($0.rounded(.up)) })
        case .quotaExceeded, .limitExceeded:
            return CommunityError.quotaExceeded
        case .partialFailure:
            if let first = ck.partialErrorsByItemID?.values.first { return communityError(for: first) }
            return CommunityError.service("iCloud couldn’t save that. Try again later.")
        case .operationCancelled:
            return CancellationError()
        case .badContainer, .missingEntitlement, .invalidArguments, .unknownItem, .badDatabase, .permissionFailure:
            return CommunityError.notSetUp
        case .serverRecordChanged:
            return CommunityError.service("Your previous answer was still syncing. Try again.")
        default:
            return CommunityError.service("iCloud error \(ck.code.rawValue). Try again later.")
        }
    }
}
