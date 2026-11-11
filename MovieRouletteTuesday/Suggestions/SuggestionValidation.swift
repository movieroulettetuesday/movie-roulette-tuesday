import Foundation

struct WatchSuggestionDraft: Equatable, Sendable {
    var movieId: String
    var why: String
}

struct AcceptedSuggestion: Equatable, Sendable {
    var movieId: String
    var why: String
}

enum SuggestionOutcome: Equatable, Sendable {
    case suggestion(AcceptedSuggestion)
    case offerSpin(SuggestionSpinReason)
    case notReady
}

enum SuggestionSpinReason: Equatable, Sendable {
    case unavailable
    case failed
}

enum SuggestionValidation {
    /// A suggestion is shown only when `movieId` is in the catalog and `why` is not empty.
    static func accept(_ draft: WatchSuggestionDraft, catalogIDs: Set<String>) -> AcceptedSuggestion? {
        let id = draft.movieId.trimmingCharacters(in: .whitespacesAndNewlines)
        let why = draft.why.trimmingCharacters(in: .whitespacesAndNewlines)
        guard catalogIDs.contains(id), !why.isEmpty else { return nil }
        return AcceptedSuggestion(movieId: id, why: why)
    }
}

enum SuggestionResolver {
    /// At most two attempts. The first valid catalog id with a non-empty why wins.
    /// A second failure (invalid id, empty why, or a thrown error) falls back to offering Spin.
    static func resolve(
        attempts: [Result<WatchSuggestionDraft, Error>],
        catalogIDs: Set<String>
    ) -> SuggestionOutcome {
        for attempt in attempts.prefix(2) {
            switch attempt {
            case .success(let draft):
                if let accepted = SuggestionValidation.accept(draft, catalogIDs: catalogIDs) {
                    return .suggestion(accepted)
                }
            case .failure:
                continue
            }
        }
        return .offerSpin(.failed)
    }
}
