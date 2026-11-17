import Foundation

/// 1.1 natural-language search: the parsed filter, its validation, chips,
/// the list-switch rule, and the deterministic `apply` step. No model here —
/// the on-device parse (iOS 26+) lives in `NLSearchParser.swift`; this file
/// compiles on iOS 17 and is unit-tested exactly.
///
/// Contract: `/workspace/mrt-shared/nl-search-filter-schema.md` (MRT Android
/// mirrors it). All set fields AND together and with the list's own toolbar
/// filters. Hosts and show notes are never matched.
public struct NLSearchFilter: Codable, Equatable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case movie, episode, any }
    public enum Watched: String, Codable, Sendable { case watched, unwatched, watchlist, any }

    public var title: String?
    public var kind: Kind?
    public var yearMin: Int?
    public var yearMax: Int?
    /// One of `NLSearch.genres`, exact catalog string.
    public var genre: String?
    /// A wheel category short name (`RouletteCategory.name`).
    public var category: String?
    /// Short stream/free service name; fold-contains against provider names.
    public var provider: String?
    public var freeOnly: Bool?
    /// Stars, 0.5...5 in 0.5 steps.
    public var ratingMin: Double?
    public var ratingMax: Double?
    public var unrated: Bool?
    public var watched: Watched?
    public var season: Int?
    public var episode: Int?
    public var onMyServices: Bool?

    public init(
        title: String? = nil, kind: Kind? = nil, yearMin: Int? = nil, yearMax: Int? = nil,
        genre: String? = nil, category: String? = nil, provider: String? = nil, freeOnly: Bool? = nil,
        ratingMin: Double? = nil, ratingMax: Double? = nil, unrated: Bool? = nil, watched: Watched? = nil,
        season: Int? = nil, episode: Int? = nil, onMyServices: Bool? = nil
    ) {
        self.title = title; self.kind = kind; self.yearMin = yearMin; self.yearMax = yearMax
        self.genre = genre; self.category = category; self.provider = provider; self.freeOnly = freeOnly
        self.ratingMin = ratingMin; self.ratingMax = ratingMax; self.unrated = unrated; self.watched = watched
        self.season = season; self.episode = episode; self.onMyServices = onMyServices
    }

    /// All-null (`kind: any` and `watched: any` count as null). An empty
    /// filter never reaches `apply`: the list uses keyword CatalogSearch.
    public var isEmpty: Bool {
        title == nil && (kind == nil || kind == .any) && yearMin == nil && yearMax == nil
            && genre == nil && category == nil && provider == nil && freeOnly == nil
            && ratingMin == nil && ratingMax == nil && unrated == nil
            && (watched == nil || watched == .any) && season == nil && episode == nil && onMyServices == nil
    }

    /// True when `apply` has to run CatalogSearch (title text or S#E#).
    public var hasSearchText: Bool { title != nil || season != nil || episode != nil }

    /// Title words plus S#E# tokens for CatalogSearch, or nil when none is set
    /// (never an empty query: an empty CatalogSearch query returns no hits).
    public var searchText: String? {
        var parts: [String] = []
        if let title { parts.append(title) }
        switch (season, episode) {
        case let (s?, e?): parts.append("s\(s)e\(e)")
        case let (s?, nil): parts.append("season \(s)")
        case let (nil, e?): parts.append("episode \(e)")
        case (nil, nil): break
        }
        let text = parts.joined(separator: " ")
        return CatalogSearch.Query(text).isEmpty ? nil : text
    }

    /// Fields that constrain the linked movie (episodes without a catalog
    /// movie fail any of these).
    var hasMovieLevelConstraint: Bool {
        genre != nil || category != nil || provider != nil || freeOnly == true || onMyServices == true
            || ratingMin != nil || ratingMax != nil || unrated != nil || (watched != nil && watched != .any)
    }
}

public enum NLSearch {
    // MARK: - Vocabulary (movies.json)

    /// Exactly the `Movie.genre` strings in the catalog.
    public static let genres = ["Drama", "Horror", "Sci-Fi", "Comedy", "Thriller", "Fantasy", "Action", "Romance", "Musical", "Western"]

    public struct CategoryName: Equatable, Sendable {
        public let name: String
        public let fullName: String
        public let id: String
    }

    /// The ten wheel categories (used when the loaded catalog lacks one).
    public static let categories: [CategoryName] = [
        .init(name: "Horror", fullName: "Horror & Terror", id: "cat-horror"),
        .init(name: "Cult", fullName: "Cult & Bizarre", id: "cat-cult"),
        .init(name: "Sci-Fi", fullName: "Sci-Fi & Fantasy", id: "cat-scifi"),
        .init(name: "Prestige", fullName: "Prestige Drama", id: "cat-prestige"),
        .init(name: "Action", fullName: "Action & Thrillers", id: "cat-action"),
        .init(name: "Dark Comedy", fullName: "Dark Comedy", id: "cat-dark-comedy"),
        .init(name: "Criterion", fullName: "Criterion & Classics", id: "cat-criterion"),
        .init(name: "Escape", fullName: "War, Escape & Survival", id: "cat-escape"),
        .init(name: "Love Hurts", fullName: "Love Hurts", id: "cat-love"),
        .init(name: "Listeners", fullName: "Listener Picks", id: "cat-listener"),
    ]

    static let yearRange = 1880...2100

    // MARK: - List switch (normative)

    public enum List: String, Equatable, Sendable, CaseIterable { case movies, episodes }

    public enum SwitchDecision: Equatable, Sendable {
        case stay
        case switchTo(List)
    }

    /// `movie` / `episode` select that list; `any` or nil stay put. Already
    /// on the named list: stay (do not reset the detail or clear the query).
    public static func listSwitch(kind: NLSearchFilter.Kind?, showing: List) -> SwitchDecision {
        let target: List
        switch kind {
        case .movie?: target = .movies
        case .episode?: target = .episodes
        case .any?, nil: return .stay
        }
        return target == showing ? .stay : .switchTo(target)
    }

    // MARK: - Question detection

    private static let triggerWords: Set<String> = [
        "find", "what", "whats", "which", "show", "recommend", "suggest", "something", "anything",
        "free", "unwatched", "unseen", "watched", "seen", "watchlist", "unrated", "rated", "rating", "stars",
        "movies", "films", "episodes", "season", "episode", "between", "before", "after", "since", "from",
        "havent", "hasnt", "didnt", "decade",
    ]

    /// Whether a query in the existing search field reads as a request for the
    /// model rather than a title. Short title-like queries ("the thing",
    /// "shudder") and anything that is a catalog title or title prefix stay on
    /// CatalogSearch. Used only when the model is available.
    public static func looksLikeQuestion(_ raw: String, titles: [String] = []) -> Bool {
        let folded = CatalogSearch.fold(raw)
        let tokens = folded.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return false }
        let text = CatalogSearch.droppingArticle(folded)
        if titles.contains(where: { title in
            guard let rank = CatalogSearch.titleRank(title, text: text) else { return false }
            return rank <= .titlePrefix
        }) { return false }
        if tokens.count >= 5 { return true }
        let query = CatalogSearch.Query(raw)
        if query.season != nil || query.episode != nil { return true }
        for (index, token) in tokens.enumerated() {
            if triggerWords.contains(token) { return true }
            if isDecade(token) { return true }
            // "on Shudder", "on my services".
            if token == "on", index + 1 < tokens.count { return true }
        }
        return false
    }

    /// "80s", "1980s".
    static func isDecade(_ token: String) -> Bool {
        guard token.hasSuffix("0s") else { return false }
        let digits = token.dropLast()
        guard digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }
        if digits.count == 2 { return true }
        if digits.count == 4, let n = Int(digits) { return yearRange.contains(n) }
        return false
    }

    // MARK: - Validation

    /// Stream and free provider names in the catalog (rent/buy excluded).
    public static func streamAndFreeProviderNames(_ catalog: MovieCatalog?) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for movie in catalog?.movies ?? [] {
            guard let s = movie.streaming else { continue }
            for p in s.stream + s.free where seen.insert(p.name).inserted { names.append(p.name) }
        }
        return names
    }

    static func categoryTable(_ catalog: MovieCatalog?) -> [CategoryName] {
        var table: [CategoryName] = []
        for c in catalog?.categories ?? [] {
            table.append(.init(name: c.name, fullName: c.fullName ?? c.name, id: c.id))
        }
        for c in categories where !table.contains(where: { $0.id == c.id }) { table.append(c) }
        return table
    }

    static func resolveCategory(_ raw: String, catalog: MovieCatalog?) -> CategoryName? {
        let folded = CatalogSearch.fold(raw)
        guard !folded.isEmpty else { return nil }
        return categoryTable(catalog).first {
            CatalogSearch.fold($0.name) == folded || CatalogSearch.fold($0.fullName) == folded
        }
    }

    /// The shared provider rule (schema "Validation details"; agreed with
    /// Android, Nov 17 2026), used by both `validated` and `apply`. A query
    /// that folds to fewer than 2 characters never matches. Otherwise the
    /// folded name must contain the whole folded query, or, only when every
    /// query word folds to at least 2 characters, contain every word.
    static func providerNameMatches(_ name: String, _ foldedQuery: String) -> Bool {
        guard foldedQuery.count >= 2 else { return false }
        let folded = CatalogSearch.fold(name)
        if folded.contains(foldedQuery) { return true }
        let words = foldedQuery.split(separator: " ")
        guard !words.isEmpty, words.allSatisfy({ $0.count >= 2 }) else { return false }
        return words.allSatisfy { folded.contains($0) }
    }

    /// Cleans a parse so only catalog vocabulary can reach `apply`: unknown
    /// genres, categories, and providers (including rent/buy-only names) are
    /// nulled. Out-of-range values are dropped, never clamped (Matthew, Nov 17
    /// 2026): a year outside 1880–2100 and a rating that is not finite or is
    /// outside 0.5–5 become nil, each bound on its own; ratings in range round
    /// to the nearest half star (ties away from zero); reversed pairs swap.
    /// `unrated: true` drops min/max; `any` becomes nil.
    public static func validated(_ raw: NLSearchFilter, catalog: MovieCatalog?) -> NLSearchFilter {
        var f = raw
        if let t = f.title?.trimmingCharacters(in: .whitespacesAndNewlines), !CatalogSearch.fold(t).isEmpty {
            f.title = t
        } else {
            f.title = nil
        }
        if f.kind == .any { f.kind = nil }
        if f.watched == .any { f.watched = nil }
        // false is "no filter" for these two (only true narrows the list).
        if f.freeOnly == false { f.freeOnly = nil }
        if f.onMyServices == false { f.onMyServices = nil }

        if let y = f.yearMin, !yearRange.contains(y) { f.yearMin = nil }
        if let y = f.yearMax, !yearRange.contains(y) { f.yearMax = nil }
        if let a = f.yearMin, let b = f.yearMax, a > b { f.yearMin = b; f.yearMax = a }

        if let g = f.genre {
            let folded = CatalogSearch.fold(g)
            f.genre = genres.first { CatalogSearch.fold($0) == folded }
        }
        if let c = f.category { f.category = resolveCategory(c, catalog: catalog)?.name }

        if let p = f.provider?.trimmingCharacters(in: .whitespacesAndNewlines) {
            let folded = CatalogSearch.fold(p)
            let known = streamAndFreeProviderNames(catalog).contains { providerNameMatches($0, folded) }
            f.provider = known ? p : nil
        }

        func stars(_ value: Double?) -> Double? {
            // Range check on the raw value, then round to the nearest half
            // star with ties away from zero (3.25 → 3.5, 4.75 → 5).
            guard let value, value.isFinite, (0.5...5).contains(value) else { return nil }
            return (value * 2).rounded(.toNearestOrAwayFromZero) / 2
        }
        f.ratingMin = stars(f.ratingMin)
        f.ratingMax = stars(f.ratingMax)
        if let a = f.ratingMin, let b = f.ratingMax, a > b { f.ratingMin = b; f.ratingMax = a }
        if f.unrated == true { f.ratingMin = nil; f.ratingMax = nil }

        if let s = f.season, !(1...999).contains(s) { f.season = nil }
        if let e = f.episode, !(1...9999).contains(e) { f.episode = nil }
        return f
    }

    // MARK: - Apply

    public struct MovieResult: Equatable, Sendable {
        /// CatalogSearch rank order when the filter has title or S#E#;
        /// otherwise folded title, then year, then id.
        public var movies: [Movie]
        /// Empty when CatalogSearch was not called.
        public var ranks: [String: CatalogSearch.Rank]
    }

    /// Runs a validated, non-empty filter on `movies` (already narrowed by the
    /// Movies toolbar). Hard filters first; CatalogSearch only on the
    /// surviving set and only when title or S#E# is set.
    public static func apply(
        _ filter: NLSearchFilter,
        toMovies movies: [Movie],
        catalog: MovieCatalog?,
        ratings: PersonalRatings,
        services: MyServices,
        episodesByGUID: [String: PodcastEpisode] = [:]
    ) -> MovieResult {
        let categoryID = filter.category.flatMap { resolveCategory($0, catalog: catalog)?.id }
        let kept = movies.filter { movie in
            if !matchesYear(movie.year, filter) { return false }
            return matchesMovieLevel(movie, filter, categoryID: categoryID, ratings: ratings, services: services)
        }
        guard let text = filter.searchText else {
            let sorted = kept.sorted { lhs, rhs in
                let l = CatalogSearch.fold(lhs.title), r = CatalogSearch.fold(rhs.title)
                if l != r { return l < r }
                if lhs.year != rhs.year { return lhs.year < rhs.year }
                return lhs.id < rhs.id
            }
            return MovieResult(movies: sorted, ranks: [:])
        }
        let hits = CatalogSearch.movies(kept, matching: text, catalog: catalog, episodesByGUID: episodesByGUID)
        return MovieResult(
            movies: hits.map(\.movie),
            ranks: Dictionary(hits.map { ($0.movie.id, $0.rank) }, uniquingKeysWith: { first, _ in first })
        )
    }

    /// Episodes: movie-level fields test the linked catalog movie (no linked
    /// movie fails them); years test the linked movie's year, or the pub year
    /// when there is no linked movie. CatalogSearch order when title or S#E#
    /// is set; otherwise the incoming (feed) order.
    public static func apply(
        _ filter: NLSearchFilter,
        toEpisodes episodes: [PodcastEpisode],
        catalog: MovieCatalog?,
        ratings: PersonalRatings,
        services: MyServices,
        calendar: Calendar = .current
    ) -> [PodcastEpisode] {
        var movieByGUID: [String: Movie] = [:]
        for movie in catalog?.movies ?? [] {
            for guid in movie.episodeIds where movieByGUID[guid] == nil { movieByGUID[guid] = movie }
        }
        let categoryID = filter.category.flatMap { resolveCategory($0, catalog: catalog)?.id }
        let kept = episodes.filter { episode in
            let movie = movieByGUID[episode.guid]
            if filter.yearMin != nil || filter.yearMax != nil {
                let year = movie?.year ?? episode.pubDate.map { calendar.component(.year, from: $0) }
                guard let year, matchesYear(year, filter) else { return false }
            }
            if filter.hasMovieLevelConstraint {
                guard let movie else { return false }
                return matchesMovieLevel(movie, filter, categoryID: categoryID, ratings: ratings, services: services)
            }
            return true
        }
        guard let text = filter.searchText else { return kept }
        return CatalogSearch.episodes(kept, matching: text, catalog: catalog, calendar: calendar).map(\.episode)
    }

    static func matchesYear(_ year: Int, _ f: NLSearchFilter) -> Bool {
        if let a = f.yearMin, year < a { return false }
        if let b = f.yearMax, year > b { return false }
        return true
    }

    static func matchesMovieLevel(
        _ movie: Movie,
        _ f: NLSearchFilter,
        categoryID: String?,
        ratings: PersonalRatings,
        services: MyServices
    ) -> Bool {
        if let genre = f.genre, movie.genre != genre { return false }
        if f.category != nil {
            guard let categoryID, movie.categories.contains(categoryID) else { return false }
        }
        if f.freeOnly == true, movie.streaming?.free.isEmpty ?? true { return false }
        if let provider = f.provider {
            let folded = CatalogSearch.fold(provider)
            guard let s = movie.streaming else { return false }
            let names = (f.freeOnly == true ? s.free : s.stream + s.free).map(\.name)
            guard names.contains(where: { providerNameMatches($0, folded) }) else { return false }
        }
        if f.onMyServices == true, !StreamingCatalog.isOnMyServices(movie, services: services) { return false }

        let half = ratings.halfStars(for: movie.id)
        if f.unrated == true {
            if half != nil { return false }
        } else {
            if f.unrated == false, half == nil { return false }
            if let lo = f.ratingMin {
                guard let half, half >= Int((lo * 2).rounded()) else { return false }
            }
            if let hi = f.ratingMax {
                guard let half, half <= Int((hi * 2).rounded()) else { return false }
            }
        }

        let status = ratings.status(for: movie.id)
        switch f.watched {
        case .watched?: if status != .watched { return false }
        case .unwatched?: if status == .watched { return false }
        case .watchlist?: if status != .wantToWatch { return false }
        case .any?, nil: break
        }
        return true
    }

    // MARK: - Chips

    public enum ChipField: String, CaseIterable, Sendable {
        case title, seasonEpisode, years, genre, category, provider, free, rating, watched, onMyServices
    }

    public struct Chip: Equatable, Identifiable, Sendable {
        public var field: ChipField
        public var label: String
        public var id: String { field.rawValue }
    }

    /// One removable chip per set field. `kind` is not a chip: it only picks
    /// the list.
    public static func chips(for f: NLSearchFilter, catalog: MovieCatalog?) -> [Chip] {
        var out: [Chip] = []
        if let title = f.title { out.append(.init(field: .title, label: "Title: \(title)")) }
        switch (f.season, f.episode) {
        case let (s?, e?): out.append(.init(field: .seasonEpisode, label: "S\(s)E\(e)"))
        case let (s?, nil): out.append(.init(field: .seasonEpisode, label: "Season \(s)"))
        case let (nil, e?): out.append(.init(field: .seasonEpisode, label: "Episode \(e)"))
        case (nil, nil): break
        }
        switch (f.yearMin, f.yearMax) {
        case let (a?, b?): out.append(.init(field: .years, label: a == b ? "\(a)" : "\(a)–\(b)"))
        case let (a?, nil): out.append(.init(field: .years, label: "\(a) or later"))
        case let (nil, b?): out.append(.init(field: .years, label: "\(b) or earlier"))
        case (nil, nil): break
        }
        if let genre = f.genre { out.append(.init(field: .genre, label: genre)) }
        if let category = f.category {
            let label = resolveCategory(category, catalog: catalog)?.fullName ?? category
            out.append(.init(field: .category, label: label))
        }
        if f.freeOnly == true { out.append(.init(field: .free, label: "Free")) }
        if let provider = f.provider { out.append(.init(field: .provider, label: "On \(provider)")) }
        if f.unrated == true {
            out.append(.init(field: .rating, label: "Unrated"))
        } else {
            switch (f.ratingMin, f.ratingMax) {
            case let (a?, b?):
                out.append(.init(field: .rating, label: a == b ? "Rated \(starLabel(a))★" : "\(starLabel(a))–\(starLabel(b))★"))
            case let (a?, nil): out.append(.init(field: .rating, label: "\(starLabel(a))★ and up"))
            case let (nil, b?): out.append(.init(field: .rating, label: "Up to \(starLabel(b))★"))
            case (nil, nil): if f.unrated == false { out.append(.init(field: .rating, label: "Rated")) }
            }
        }
        switch f.watched {
        case .watched?: out.append(.init(field: .watched, label: "Watched"))
        case .unwatched?: out.append(.init(field: .watched, label: "Unwatched"))
        case .watchlist?: out.append(.init(field: .watched, label: "Watchlist"))
        case .any?, nil: break
        }
        if f.onMyServices == true { out.append(.init(field: .onMyServices, label: "On my services")) }
        return out
    }

    static func starLabel(_ stars: Double) -> String { HalfStars.label(stars: stars) }

    /// The filter with one chip's field(s) cleared.
    public static func removing(_ field: ChipField, from f: NLSearchFilter) -> NLSearchFilter {
        var f = f
        switch field {
        case .title: f.title = nil
        case .seasonEpisode: f.season = nil; f.episode = nil
        case .years: f.yearMin = nil; f.yearMax = nil
        case .genre: f.genre = nil
        case .category: f.category = nil
        case .provider: f.provider = nil
        case .free: f.freeOnly = nil
        case .rating: f.ratingMin = nil; f.ratingMax = nil; f.unrated = nil
        case .watched: f.watched = nil
        case .onMyServices: f.onMyServices = nil
        }
        return f
    }
}
