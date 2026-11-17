import Foundation
import Observation

/// Turns a question into an `NLSearchFilter`. The live parser is the on-device
/// Foundation Model (iOS 26+); tests and DEBUG UI tests inject a stub.
protocol NLSearchParsing: Sendable {
    func parse(_ question: String) async throws -> NLSearchFilter
    /// Loads the model ahead of the first question. Optional.
    func prewarm()
}

extension NLSearchParsing {
    func prewarm() {}
}

enum NLSearchError: Error, Equatable {
    case timeout
    case noParse
}

/// Returns a fixed filter per question (folded). Unknown questions throw, the
/// same as a failed parse, so the list stays on keyword search.
struct StubNLSearchParser: NLSearchParsing {
    let table: [String: NLSearchFilter]

    init(_ table: [String: NLSearchFilter]) {
        var folded: [String: NLSearchFilter] = [:]
        for (question, filter) in table { folded[CatalogSearch.fold(question)] = filter }
        self.table = folded
    }

    func parse(_ question: String) async throws -> NLSearchFilter {
        guard let filter = table[CatalogSearch.fold(question)] else { throw NLSearchError.noParse }
        return filter
    }
}

/// Search state for the Movies and Episodes lists, owned by `ContentView` so
/// a question can hand its query and chips from one tab to the other.
///
/// With the model unavailable (iOS < 26, ineligible device, Apple
/// Intelligence off, model not ready) nothing here parses: `filter` stays nil
/// and both lists run keyword CatalogSearch exactly as before.
@MainActor
@Observable
final class NLSearchModel {
    struct ListState: Equatable {
        /// The list's `.searchable` text.
        var query = ""
        /// The list's `.searchable` presentation. A handoff dismisses the
        /// source's search (no keyboard waiting there); it never presents the
        /// destination's.
        var searchPresented = false
        /// Validated, non-empty parse of `parsedQuery`. nil means keyword search.
        var filter: NLSearchFilter?
        /// The question the last parse (successful or not) was for, so
        /// reappearing or a chip removal never re-parses the same text.
        var parsedQuery: String?
        /// Bumped when a question hands off to this list: it pops to its root
        /// and (iPad) resets the detail column.
        var resetToken = 0
    }

    enum Outcome: Equatable {
        /// Nothing to do (same question already parsed, or the text changed while parsing).
        case skipped
        /// Keyword CatalogSearch on the raw query (not a question, unavailable, empty or failed parse).
        case keyword
        /// Chips on the current list.
        case chips
        /// Query and chips moved to the other list.
        case switched(NLSearch.List)
    }

    var movies = ListState()
    var episodes = ListState()

    private let availability: @MainActor () -> SuggestionModelStatus
    private let makeParser: @MainActor () -> (any NLSearchParsing)?
    @ObservationIgnored private var cachedParser: (any NLSearchParsing)?
    @ObservationIgnored var timeout: Duration = .seconds(2)
    @ObservationIgnored private var didPrewarm = false

    /// After the last keystroke, before a question goes to the model.
    static let debounce: Duration = .milliseconds(400)

    init(
        availability: @escaping @MainActor () -> SuggestionModelStatus = { NLSearchAvailability.current() },
        makeParser: @escaping @MainActor () -> (any NLSearchParsing)? = { NLSearchParserFactory.make() }
    ) {
        self.availability = availability
        self.makeParser = makeParser
    }

    /// Only `.available` uses the model. `.modelNotReady` keeps keyword search
    /// and is checked again on the next debounce.
    var isEnabled: Bool { availability() == .available }

    subscript(list: NLSearch.List) -> ListState {
        get { list == .movies ? movies : episodes }
        set { if list == .movies { movies = newValue } else { episodes = newValue } }
    }

    private var parser: (any NLSearchParsing)? {
        if let cachedParser { return cachedParser }
        cachedParser = makeParser()
        return cachedParser
    }

    /// When Movies or Episodes first appears.
    func prewarm() {
        guard !didPrewarm, isEnabled, let parser else { return }
        didPrewarm = true
        parser.prewarm()
    }

    /// Synchronous step on every edit: anything that is not a question for an
    /// available model drops the chips at once. A question keeps the last
    /// good chips showing until its parse lands.
    func queryChanged(_ list: NLSearch.List, titles: [String]) {
        var state = self[list]
        guard state.query != state.parsedQuery else { return }
        if !isEnabled || !NLSearch.looksLikeQuestion(state.query, titles: titles) {
            guard state.filter != nil || state.parsedQuery != nil else { return }
            state.filter = nil
            state.parsedQuery = nil
            self[list] = state
        }
    }

    /// The debounced step: parse (2 s timeout), validate, then stay or hand
    /// off. Any failure falls back to keyword search with no switch.
    @discardableResult
    func parse(
        _ list: NLSearch.List,
        catalog: MovieCatalog?,
        switchTab: (NLSearch.List) -> Void
    ) async -> Outcome {
        let question = self[list].query
        guard question != self[list].parsedQuery else { return .skipped }
        let titles = catalog?.movies.map(\.title) ?? []
        guard isEnabled, NLSearch.looksLikeQuestion(question, titles: titles), let parser else {
            queryChanged(list, titles: titles)
            return .keyword
        }
        let raw: NLSearchFilter?
        do {
            raw = try await Self.withTimeout(timeout) { try await parser.parse(question) }
        } catch {
            raw = nil
        }
        // The field changed (or a handoff cleared it) while the model ran.
        guard self[list].query == question else { return .skipped }
        return handle(raw, question: question, from: list, catalog: catalog, switchTab: switchTab)
    }

    /// Applies one parse result (or nil for a failure). Separate from `parse`
    /// so tests can drive the switch rule without timing.
    @discardableResult
    func handle(
        _ raw: NLSearchFilter?,
        question: String,
        from list: NLSearch.List,
        catalog: MovieCatalog?,
        switchTab: (NLSearch.List) -> Void
    ) -> Outcome {
        guard let raw else {
            self[list].filter = nil
            self[list].parsedQuery = question
            return .keyword
        }
        let filter = NLSearch.validated(raw, catalog: catalog)
        guard !filter.isEmpty else {
            self[list].filter = nil
            self[list].parsedQuery = question
            return .keyword
        }
        switch NLSearch.listSwitch(kind: filter.kind, showing: list) {
        case .stay:
            self[list].filter = filter
            self[list].parsedQuery = question
            return .chips
        case .switchTo(let destination):
            var arriving = self[destination]
            arriving.query = question
            arriving.filter = filter
            arriving.parsedQuery = question
            arriving.resetToken += 1
            self[destination] = arriving
            // Clear the source so going back does not bounce forward again.
            var leaving = self[list]
            leaving.query = ""
            leaving.filter = nil
            leaving.parsedQuery = nil
            leaving.searchPresented = false
            self[list] = leaving
            switchTab(destination)
            return .switched(destination)
        }
    }

    /// Clears one chip's field. When no chip is left the list goes back to
    /// keyword search on the raw text (an all-null filter never reaches apply).
    func removeChip(_ field: NLSearch.ChipField, from list: NLSearch.List, catalog: MovieCatalog?) {
        guard let filter = self[list].filter else { return }
        let next = NLSearch.removing(field, from: filter)
        self[list].filter = NLSearch.chips(for: next, catalog: catalog).isEmpty ? nil : next
    }

    func chips(_ list: NLSearch.List, catalog: MovieCatalog?) -> [NLSearch.Chip] {
        self[list].filter.map { NLSearch.chips(for: $0, catalog: catalog) } ?? []
    }

    nonisolated static func withTimeout(
        _ limit: Duration,
        _ operation: @escaping @Sendable () async throws -> NLSearchFilter
    ) async throws -> NLSearchFilter {
        try await withThrowingTaskGroup(of: NLSearchFilter.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: limit)
                throw NLSearchError.timeout
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw NLSearchError.timeout }
            return first
        }
    }
}
