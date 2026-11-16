import Foundation

/// One matcher for every search surface: the Movies and Episodes lists, the
/// tvOS Search tab, and the Siri / Shortcuts entity queries. Local data only
/// (bundled or cached catalog, cached RSS episodes); no network.
///
/// Rules (MRT Android mirrors these exactly):
/// - `fold`: lowercase, strip diacritics, delete apostrophes (' ’ ‘ ʼ ` ´),
///   turn every other run of non-letters/non-digits into one space, trim.
/// - Query tokens: `s4e39`, `s4 e39`, `4x39`, `season 4 episode 39` set a season
///   and/or episode; `e39`, `ep39`, `ep 39`, `episode 39` set an episode number;
///   the first 4-digit number in 1880...2100 sets a year. Everything else is text.
///   A leading "the" / "a" / "an" is dropped from the text when words remain.
/// - Season/episode and year are filters. A year also stays in the text for
///   titles that contain it ("2001", "Blade Runner 2049").
/// - Ranks, best first: exact title, title prefix, title words (substring or
///   every word somewhere in the title), episode (S#E#, episode number, or the
///   linked episode / movie title), year only, genre or category, streaming
///   provider (stream + free lists only; secondary). Hosts and show notes are
///   never searched.
public enum CatalogSearch {
    public enum Rank: Int, Comparable, Sendable, CaseIterable {
        case exactTitle = 0
        case titlePrefix
        case titleWords
        case episode
        case year
        case genreOrCategory
        case provider

        public static func < (lhs: Rank, rhs: Rank) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public struct MovieHit: Equatable, Sendable {
        public let movie: Movie
        public let rank: Rank
    }

    public struct EpisodeHit: Equatable, Sendable {
        public let episode: PodcastEpisode
        public let rank: Rank
    }

    /// A parsed query. `text` has the year and S#E# tokens removed and a
    /// leading article dropped; `textWithYear` keeps the year token.
    public struct Query: Equatable, Sendable {
        public var text: String
        public var textWithYear: String
        public var year: Int?
        public var season: Int?
        public var episode: Int?

        public var isEmpty: Bool { text.isEmpty && year == nil && season == nil && episode == nil }
        var words: [String] { text.split(separator: " ").map(String.init) }
        var hasEpisodeFilter: Bool { season != nil || episode != nil }

        public init(_ raw: String) {
            let tokens = CatalogSearch.fold(raw).split(separator: " ").map(String.init)
            var textTokens: [String] = []
            var withYear: [String] = []
            var year: Int?
            var season: Int?
            var episode: Int?
            var i = 0
            func number(_ s: String, maxDigits: Int) -> Int? {
                guard !s.isEmpty, s.count <= maxDigits, s.allSatisfy(\.isASCIIDigit) else { return nil }
                return Int(s)
            }
            func next(_ offset: Int) -> String? { tokens.indices.contains(i + offset) ? tokens[i + offset] : nil }
            while i < tokens.count {
                let token = tokens[i]
                if let pair = Self.seasonEpisode(token) {
                    season = pair.0; episode = pair.1; i += 1; continue
                }
                if token.hasPrefix("s"), let s = number(String(token.dropFirst()), maxDigits: 3),
                   let nextToken = next(1), nextToken.hasPrefix("e"), let e = number(String(nextToken.dropFirst()), maxDigits: 4) {
                    season = s; episode = e; i += 2; continue
                }
                if token == "season", let n = next(1).flatMap({ number($0, maxDigits: 3) }) {
                    season = n; i += 2; continue
                }
                if token == "episode" || token == "ep", let n = next(1).flatMap({ number($0, maxDigits: 4) }) {
                    episode = n; i += 2; continue
                }
                if token.hasPrefix("ep"), let n = number(String(token.dropFirst(2)), maxDigits: 4) {
                    episode = n; i += 1; continue
                }
                if token.hasPrefix("e"), let n = number(String(token.dropFirst()), maxDigits: 4) {
                    episode = n; i += 1; continue
                }
                if year == nil, let n = number(token, maxDigits: 4), token.count == 4, (1880...2100).contains(n) {
                    year = n; withYear.append(token); i += 1; continue
                }
                textTokens.append(token)
                withYear.append(token)
                i += 1
            }
            self.text = CatalogSearch.droppingArticle(textTokens.joined(separator: " "))
            self.textWithYear = CatalogSearch.droppingArticle(withYear.joined(separator: " "))
            self.year = year
            self.season = season
            self.episode = episode
        }

        /// "s4e39" or "4x39".
        private static func seasonEpisode(_ token: String) -> (Int, Int)? {
            let separators: [(prefix: String, mid: Character)] = [("s", "e"), ("", "x")]
            for (prefix, mid) in separators {
                guard token.hasPrefix(prefix) else { continue }
                let body = token.dropFirst(prefix.count)
                guard let split = body.firstIndex(of: mid) else { continue }
                let left = body[..<split]
                let right = body[body.index(after: split)...]
                guard !left.isEmpty, left.count <= 3, left.allSatisfy(\.isASCIIDigit),
                      !right.isEmpty, right.count <= 4, right.allSatisfy(\.isASCIIDigit),
                      let s = Int(left), let e = Int(right) else { continue }
                return (s, e)
            }
            return nil
        }
    }

    // MARK: - Normalization

    static let apostrophes: Set<Unicode.Scalar> = ["'", "\u{2019}", "\u{2018}", "\u{02BC}", "`", "\u{00B4}"]

    /// Lowercased, diacritics stripped, apostrophes deleted, other punctuation
    /// and whitespace collapsed to single spaces.
    public static func fold(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        var out = String.UnicodeScalarView()
        var pendingSpace = false
        for scalar in folded.unicodeScalars {
            if apostrophes.contains(scalar) { continue }
            if CharacterSet.alphanumerics.contains(scalar) {
                if pendingSpace, !out.isEmpty { out.append(" ") }
                pendingSpace = false
                out.append(scalar)
            } else {
                pendingSpace = true
            }
        }
        return String(out)
    }

    /// Drops one leading "the", "a", or "an" when something follows it.
    static func droppingArticle(_ folded: String) -> String {
        for article in ["the ", "a ", "an "] where folded.hasPrefix(article) {
            let rest = String(folded.dropFirst(article.count))
            if !rest.isEmpty { return rest }
        }
        return folded
    }

    // MARK: - Movies

    /// Ranked hits, best first; ties by folded title, then year. An empty or
    /// punctuation-only query returns no hits (lists show everything instead).
    public static func movies(
        _ movies: [Movie],
        matching raw: String,
        catalog: MovieCatalog?,
        episodesByGUID: [String: PodcastEpisode] = [:]
    ) -> [MovieHit] {
        let query = Query(raw)
        guard !query.isEmpty else { return [] }
        let categoryNames = categoryLookup(catalog)
        let hits = movies.compactMap { movie -> MovieHit? in
            rank(movie, query: query, categoryNames: categoryNames, episodesByGUID: episodesByGUID)
                .map { MovieHit(movie: movie, rank: $0) }
        }
        return hits.sorted { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            let l = fold(lhs.movie.title), r = fold(rhs.movie.title)
            if l != r { return l < r }
            if lhs.movie.year != rhs.movie.year { return lhs.movie.year < rhs.movie.year }
            return lhs.movie.id < rhs.movie.id
        }
    }

    static func rank(
        _ movie: Movie,
        query: Query,
        categoryNames: [String: [String]],
        episodesByGUID: [String: PodcastEpisode]
    ) -> Rank? {
        if query.hasEpisodeFilter {
            let linked = movie.episodeIds.compactMap { episodesByGUID[$0] }
            guard linked.contains(where: { matchesEpisodeFilter($0, query) }) else { return nil }
        }
        var best: Rank?
        if query.year != nil, query.textWithYear != query.text, let r = titleRank(movie.title, text: query.textWithYear) {
            best = r
        }
        if query.year == nil || movie.year == query.year {
            if query.text.isEmpty {
                best = minRank(best, query.hasEpisodeFilter ? .episode : .year)
            } else {
                best = minRank(best, textRank(movie, query: query, categoryNames: categoryNames, episodesByGUID: episodesByGUID))
            }
        }
        return best
    }

    private static func textRank(
        _ movie: Movie,
        query: Query,
        categoryNames: [String: [String]],
        episodesByGUID: [String: PodcastEpisode]
    ) -> Rank? {
        if let r = titleRank(movie.title, text: query.text) { return r }
        let episodeTitles = [movie.episodeTitle].compactMap { $0 } + movie.episodeIds.compactMap { episodesByGUID[$0]?.title }
        if episodeTitles.contains(where: { contains(fold($0), query) }) { return .episode }
        let fields = [movie.genre] + movie.categories.flatMap { categoryNames[$0] ?? [] }
        if fields.contains(where: { contains(fold($0), query) }) { return .genreOrCategory }
        if let streaming = movie.streaming,
           (streaming.stream + streaming.free).contains(where: { contains(fold($0.name), query) }) {
            return .provider
        }
        return nil
    }

    // MARK: - Episodes

    /// Ranked hits, best first; ties newest first, then folded title.
    public static func episodes(
        _ episodes: [PodcastEpisode],
        matching raw: String,
        catalog: MovieCatalog?,
        calendar: Calendar = .current
    ) -> [EpisodeHit] {
        let query = Query(raw)
        guard !query.isEmpty else { return [] }
        let categoryNames = categoryLookup(catalog)
        var movieByGUID: [String: Movie] = [:]
        for movie in catalog?.movies ?? [] {
            for guid in movie.episodeIds where movieByGUID[guid] == nil { movieByGUID[guid] = movie }
        }
        let hits = episodes.compactMap { episode -> EpisodeHit? in
            rank(episode, query: query, movie: movieByGUID[episode.guid], categoryNames: categoryNames, calendar: calendar)
                .map { EpisodeHit(episode: episode, rank: $0) }
        }
        return hits.sorted { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            let l = lhs.episode.pubDate ?? .distantPast, r = rhs.episode.pubDate ?? .distantPast
            if l != r { return l > r }
            return fold(lhs.episode.title) < fold(rhs.episode.title)
        }
    }

    static func rank(
        _ episode: PodcastEpisode,
        query: Query,
        movie: Movie?,
        categoryNames: [String: [String]],
        calendar: Calendar
    ) -> Rank? {
        if query.hasEpisodeFilter, !matchesEpisodeFilter(episode, query) { return nil }
        var best: Rank?
        if query.year != nil, query.textWithYear != query.text, let r = titleRank(episode.title, text: query.textWithYear) {
            best = r
        }
        let pubYear = episode.pubDate.map { calendar.component(.year, from: $0) }
        if let year = query.year, pubYear != year, movie?.year != year { return best }
        if query.text.isEmpty {
            return minRank(best, query.hasEpisodeFilter ? .episode : .year)
        }
        if let r = titleRank(episode.title, text: query.text) { return minRank(best, r) }
        guard let movie else { return best }
        if titleRank(movie.title, text: query.text) != nil { return minRank(best, .episode) }
        let fields = [movie.genre] + movie.categories.flatMap { categoryNames[$0] ?? [] }
        if fields.contains(where: { contains(fold($0), query) }) { return minRank(best, .genreOrCategory) }
        if let streaming = movie.streaming,
           (streaming.stream + streaming.free).contains(where: { contains(fold($0.name), query) }) {
            return minRank(best, .provider)
        }
        return best
    }

    // MARK: - Helpers

    static func titleRank(_ title: String, text: String) -> Rank? {
        guard !text.isEmpty else { return nil }
        let full = fold(title)
        let bare = droppingArticle(full)
        if bare == text || full == text { return .exactTitle }
        if bare.hasPrefix(text) || full.hasPrefix(text) { return .titlePrefix }
        let words = text.split(separator: " ")
        if full.contains(text) || words.allSatisfy({ full.contains($0) }) { return .titleWords }
        return nil
    }

    private static func contains(_ folded: String, _ query: Query) -> Bool {
        guard !query.text.isEmpty else { return false }
        return folded.contains(query.text) || query.words.allSatisfy { folded.contains($0) }
    }

    private static func matchesEpisodeFilter(_ episode: PodcastEpisode, _ query: Query) -> Bool {
        if let season = query.season, episode.season != season { return false }
        if let number = query.episode, episode.episode != number { return false }
        return true
    }

    private static func minRank(_ a: Rank?, _ b: Rank?) -> Rank? {
        switch (a, b) {
        case let (a?, b?): return min(a, b)
        case let (a?, nil): return a
        case let (nil, b): return b
        }
    }

    private static func categoryLookup(_ catalog: MovieCatalog?) -> [String: [String]] {
        var names: [String: [String]] = [:]
        for category in catalog?.categories ?? [] {
            names[category.id] = [category.name, category.fullName].compactMap { $0 }
        }
        return names
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
