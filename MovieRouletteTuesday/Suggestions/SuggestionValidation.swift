import Foundation

/// What "Pick for Me" shows: a movie, an app-owned lead line (the vibe, or the
/// fallback line), and facts the app wrote from your own lists.
struct AcceptedSuggestion: Equatable, Sendable {
    var movieId: String
    var title: String
    var year: Int
    /// The vibe line, or the fallback line when true; nil shows facts only.
    var lead: String?
    var facts: [PickFact]
    /// True when the model didn't answer in time (or answered outside the list)
    /// and the app showed its own top candidate.
    var isFallback: Bool

    init(movieId: String, title: String, year: Int, lead: String?, facts: [PickFact], isFallback: Bool) {
        self.movieId = movieId
        self.title = title
        self.year = year
        self.lead = lead
        self.facts = facts
        self.isFallback = isFallback
    }

    init(movie: PickMovie, lead: String?, isFallback: Bool) {
        self.init(
            movieId: movie.id,
            title: movie.title,
            year: movie.year,
            lead: lead,
            facts: ReasonComposer.facts(for: movie),
            isFallback: isFallback
        )
    }

    var factsLine: String { facts.map(\.text).joined(separator: " · ") }
    var spoken: String { ReasonComposer.spoken(title: title, year: year, lead: lead, facts: facts) }
}

enum SuggestionOutcome: Equatable, Sendable {
    case suggestion(AcceptedSuggestion)
    case offerSpin(SuggestionSpinReason)
    case notReady
}

enum SuggestionSpinReason: Equatable, Sendable {
    /// The on-device model can't run here.
    case unavailable
    /// Nothing to pick from (every movie watched and none rated 4 stars), or the catalog didn't load.
    case failed
}
