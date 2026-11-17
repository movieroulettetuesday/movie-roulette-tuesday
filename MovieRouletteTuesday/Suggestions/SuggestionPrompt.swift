import Foundation

enum SuggestionPrompt {
    /// Most recent distinct movie ids, newest first, up to `limit`. Sorted by timestamp, not array order.
    static func recentIDs(from results: [SpinResult], limit: Int = 10) -> Set<String> {
        let ordered = results.sorted { $0.timestamp > $1.timestamp }
        var seen = Set<String>()
        var ids: [String] = []
        for result in ordered {
            if seen.insert(result.movieId).inserted {
                ids.append(result.movieId)
                if ids.count >= limit { break }
            }
        }
        return Set(ids)
    }
}


// "Pick for Me": the app chooses the candidates and writes every fact.
// The on-device model only returns a number from the list and a vibe from a
// fixed set, so it can't claim a watchlist entry, a rating, or a service.
// Rules are shared with Android (mrt-shared/wsiw/*.json).

/// One catalog movie as the picker sees it. Built only from local state.
struct PickMovie: Equatable, Sendable {
    var id: String
    var title: String
    var year: Int
    var genre: String
    /// Category display names, in catalog order.
    var categories: [String]
    var status: WatchStatus?
    var halfStars: Int?
    /// Among the 10 most recent spins.
    var recent: Bool
    /// First of the listener's services in the movie's stream list.
    var serviceProvider: String?
    /// First provider in the movie's free list.
    var freeProvider: String?

    var onWatchlist: Bool { status == .wantToWatch }
    /// Rating a movie marks it watched, so any rating counts.
    var isWatched: Bool { status == .watched || halfStars != nil }

    /// Watchlist +3, one of your services +2, free +1.
    var score: Int {
        (onWatchlist ? 3 : 0) + (serviceProvider != nil ? 2 : 0) + (freeProvider != nil ? 1 : 0)
    }

    static func rows(
        catalog: MovieCatalog,
        ratings: PersonalRatings,
        recentIDs: Set<String>,
        services: MyServices
    ) -> [PickMovie] {
        catalog.movies.map { movie in
            PickMovie(
                id: movie.id,
                title: movie.title,
                year: movie.year,
                genre: movie.genre,
                categories: movie.categories.compactMap { catalog.category(withId: $0)?.displayName },
                status: ratings.status(for: movie.id),
                halfStars: ratings.halfStars(for: movie.id),
                recent: recentIDs.contains(movie.id),
                serviceProvider: firstService(stream: movie.streaming?.stream ?? [], services: services),
                freeProvider: movie.streaming?.free.first?.name
            )
        }
    }

    static func firstService(stream: [StreamingInfo.Provider], services: MyServices) -> String? {
        stream.first { services.contains($0.id) }?.name
    }
}

// MARK: - Candidates

enum PickCandidates {
    static let cap = 12
    static let minimum = 3
    /// A rewatch is offered only when the listener rated it this high (4 stars).
    static let rewatchMinimumHalfStars = 8

    /// Unwatched and not recently spun, best score first, top 12. Fewer than
    /// three: allow recent spins, then add rewatches rated 4 stars or more.
    /// Equal scores keep the order of a shuffle seeded once per tap (same as
    /// Android `PickCandidates.select`). Empty means offer Spin.
    static func select<G: RandomNumberGenerator>(_ movies: [PickMovie], using rng: inout G) -> [PickMovie] {
        let unwatched = movies.filter { !$0.isWatched }
        var pool = unwatched.filter { !$0.recent }
        if pool.count < minimum { pool = unwatched }
        if pool.count < minimum {
            pool += movies.filter { ($0.halfStars ?? 0) >= rewatchMinimumHalfStars }
        }
        return Array(
            pool.shuffled(using: &rng)
                .enumerated()
                .sorted { a, b in
                    a.element.score != b.element.score ? a.element.score > b.element.score : a.offset < b.offset
                }
                .map(\.element)
                .prefix(cap)
        )
    }
}

/// Deterministic per seed, so a tap's shuffle can be reproduced in tests.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Prompt

enum PickPrompt {
    static let instructions = """
        Choose one movie for the listener tonight from the numbered list.
        Lower numbers match their watchlist and services better.
        Answer with the movie's number and one vibe that suits its genre.
        """

    /// About 20 tokens a row; 12 rows stay far under the 4,096-token context.
    static func prompt(for candidates: [PickMovie]) -> String {
        var lines = ["Movies:"]
        for (offset, movie) in candidates.enumerated() {
            lines.append("\(offset + 1). " + row(for: movie))
        }
        lines.append("Pick one number from 1 to \(candidates.count).")
        return lines.joined(separator: "\n")
    }

    static func row(for movie: PickMovie) -> String {
        var parts = ["\(movie.title) (\(movie.year))", movie.genre]
        if !movie.categories.isEmpty {
            parts.append("categories: " + movie.categories.joined(separator: ", "))
        }
        parts.append("watchlist: " + (movie.onWatchlist ? "yes" : "no"))
        parts.append("on your services: " + (movie.serviceProvider ?? "none"))
        if let free = movie.freeProvider { parts.append("free: " + free) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Vibe (the only model-chosen words, all app-owned copy)

enum PickVibe: String, CaseIterable, Sendable {
    case laughs, scares, thrills, weird, cult, feelGood, heartbreak, action, classic, dark

    var line: String {
        switch self {
        case .laughs: return "Good for a laugh."
        case .scares: return "Good for a scare."
        case .thrills: return "Edge-of-your-seat."
        case .weird: return "Gloriously weird."
        case .cult: return "A cult favourite."
        case .feelGood: return "An easy, feel-good watch."
        case .heartbreak: return "Bring tissues."
        case .action: return "Big, loud fun."
        case .classic: return "An old-school classic."
        case .dark: return "Dark and twisted."
        }
    }

    /// Which vibes fit each genre. Same table as Android `Vibes.byGenre`.
    static let byGenre: [String: [PickVibe]] = [
        "Horror": [.scares, .dark, .weird, .cult],
        "Thriller": [.thrills, .scares, .dark, .cult],
        "Comedy": [.laughs, .feelGood, .weird, .cult],
        "Action": [.action, .thrills, .cult],
        "Sci-Fi": [.weird, .thrills, .action, .dark, .cult],
        "Fantasy": [.weird, .feelGood, .action, .cult],
        "Romance": [.feelGood, .heartbreak, .laughs],
        "Musical": [.feelGood, .laughs, .weird, .cult],
        "Western": [.action, .dark],
        "Drama": [.heartbreak, .dark, .feelGood, .cult],
    ]

    /// The genre's own vibe when the model's doesn't fit. Nil (no vibe line)
    /// where no single line is safe, e.g. Drama. Same as Android `Vibes.default`.
    static let genreDefault: [String: PickVibe] = [
        "Horror": .scares, "Thriller": .thrills, "Comedy": .laughs, "Action": .action,
        "Sci-Fi": .weird, "Fantasy": .weird, "Romance": .feelGood, "Musical": .feelGood, "Western": .action,
    ]

    /// "An old-school classic." only before this year.
    static let classicBeforeYear = 1980

    func fits(genre: String, year: Int) -> Bool {
        if self == .classic { return (1..<Self.classicBeforeYear).contains(year) }
        return Self.byGenre[genre]?.contains(self) ?? false
    }

    static func fromGenre(_ genre: String) -> PickVibe? { genreDefault[genre] }

    /// The model's vibe if it fits, else the genre's own, else none.
    static func validated(_ vibe: PickVibe, genre: String, year: Int) -> PickVibe? {
        vibe.fits(genre: genre, year: year) ? vibe : fromGenre(genre)
    }
}

// MARK: - Facts (app-written, from real state only)

enum PickFact: Equatable, Sendable {
    case onWatchlist
    case notWatchedYet
    case rated(halfStars: Int)
    case streaming(String)
    case free(String)
    case category(String)

    var text: String {
        switch self {
        case .onWatchlist: return "On your watchlist"
        case .notWatchedYet: return "Not watched yet"
        case .rated(let half):
            let label = HalfStars.label(half)
            return "You rated it \(label) \(half == 2 ? "star" : "stars")"
        case .streaming(let name): return "Streaming on \(name)"
        case .free(let name): return "Free on \(name)"
        case .category(let name): return "From the \(name) category"
        }
    }
}

enum ReasonComposer {
    static func facts(for movie: PickMovie) -> [PickFact] {
        var facts: [PickFact] = []
        if movie.onWatchlist { facts.append(.onWatchlist) }
        if !movie.isWatched { facts.append(.notWatchedYet) }
        if let half = movie.halfStars { facts.append(.rated(halfStars: half)) }
        if let service = movie.serviceProvider {
            facts.append(.streaming(service))
        } else if let free = movie.freeProvider {
            facts.append(.free(free))
        }
        if let category = movie.categories.first { facts.append(.category(category)) }
        return facts
    }

    static let fallbackLine = "Picked from your watchlist and services."

    /// The no-model pick's line, only when it's true for that movie (on the
    /// watchlist, or streaming on one of your services). Otherwise no line.
    static func fallbackLead(for movie: PickMovie) -> String? {
        movie.onWatchlist || movie.serviceProvider != nil ? fallbackLine : nil
    }

    /// "Try Christmas Evil (1980). Good for a scare. It's on your watchlist and streaming on Netflix."
    /// Same order as Android `PickReason.spoken`.
    static func spoken(title: String, year: Int, lead: String?, facts: [PickFact]) -> String {
        var sentences = ["Try \(title) (\(year))."]
        if let lead { sentences.append(lead) }
        for case .rated(let half) in facts {
            sentences.append(PickFact.rated(halfStars: half).text + ".")
            break
        }
        var clauses: [String] = []
        if facts.contains(.onWatchlist) { clauses.append("on your watchlist") }
        for fact in facts {
            if case .streaming(let name) = fact { clauses.append("streaming on \(name)"); break }
            if case .free(let name) = fact { clauses.append("free on \(name)"); break }
        }
        if !clauses.isEmpty { sentences.append("It’s " + clauses.joined(separator: " and ") + ".") }
        return sentences.joined(separator: " ")
    }
}

// MARK: - Banned phrases (byte-for-byte the patterns in mrt-shared/wsiw/banned-phrases.json)

enum BannedPhrases {
    static let patterns: [String] = [
        "\\bwatch ?list\\b", "\\bwant to watch\\b", "\\bsaved\\b", "\\brat(ed|ing|ings)\\b", "\\bstars?\\b", "★",
        "\\bout of (5|five|10|ten)\\b", "\\b\\d(\\.5)?\\s*/\\s*(5|10)\\b", "\\bwatched\\b", "\\bseen\\b", "\\bhaven'?t (seen|watched)\\b",
        "\\byou (loved|liked|enjoyed)\\b", "\\bfavou?rite\\b", "\\bstream(ing|s)?\\b", "\\bfree\\b", "\\bavailable on\\b",
        "\\bawards?\\b", "\\boscars?\\b", "\\bcritics?\\b", "\\bacclaimed\\b", "\\bbox office\\b",
    ]

    private static let compiled: [NSRegularExpression] = patterns.compactMap {
        try? NSRegularExpression(pattern: $0, options: [.caseInsensitive])
    }

    /// False when model-authored text makes a claim only the app may make.
    /// Provider names from the catalog are added at runtime.
    static func isClean(_ text: String, providerNames: [String] = []) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        if compiled.contains(where: { $0.firstMatch(in: text, range: range) != nil }) { return false }
        let lower = text.lowercased()
        for name in providerNames where !name.isEmpty {
            let escaped = NSRegularExpression.escapedPattern(for: name.lowercased())
            if lower.range(of: "\\b\(escaped)\\b", options: .regularExpression) != nil { return false }
        }
        return true
    }
}

// MARK: - Model answer → what the card shows

/// Exactly what the on-device model returns.
struct RawPick: Equatable, Sendable {
    var pick: Int
    var vibe: String
}

enum PickResolution: Equatable, Sendable {
    /// `pick` is 1-based. `vibe` is nil when neither the model's vibe nor the
    /// genre's own fits; `vibeFromGenre` is true when the model's was replaced.
    case model(pick: Int, vibe: PickVibe?, vibeFromGenre: Bool)
    case templateFallback
}

enum PickResolver {
    /// One attempt, strict: no answer, a thrown error, a timeout, a number
    /// outside the list, or a vibe that isn't exactly one of the fixed values
    /// (or matches the banned list) is the app's own pick of the top candidate.
    /// A known vibe that doesn't fit the genre becomes the genre's own, or none.
    static func resolve(_ raw: RawPick?, candidates: [PickMovie], providerNames: [String]) -> PickResolution {
        guard let raw, !candidates.isEmpty, (1...candidates.count).contains(raw.pick),
              BannedPhrases.isClean(raw.vibe, providerNames: providerNames),
              let vibe = PickVibe(rawValue: raw.vibe) else {
            return .templateFallback
        }
        let movie = candidates[raw.pick - 1]
        let checked = PickVibe.validated(vibe, genre: movie.genre, year: movie.year)
        return .model(pick: raw.pick, vibe: checked, vibeFromGenre: checked != vibe)
    }

    static func accept(_ resolution: PickResolution, candidates: [PickMovie]) -> AcceptedSuggestion? {
        switch resolution {
        case .model(let pick, let vibe, _):
            guard candidates.indices.contains(pick - 1) else { return nil }
            return AcceptedSuggestion(movie: candidates[pick - 1], lead: vibe?.line, isFallback: false)
        case .templateFallback:
            guard let top = candidates.first else { return nil }
            return AcceptedSuggestion(movie: top, lead: ReasonComposer.fallbackLead(for: top), isFallback: true)
        }
    }
}
