import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Whether NL search may use the on-device model. Same states as the
/// step-2 suggestion gate; only `.available` enables the model path.
@MainActor
enum NLSearchAvailability {
    /// Unit tests set this. nil falls through to launch arguments (DEBUG) or the system.
    static var override: SuggestionModelStatus?

    static func current() -> SuggestionModelStatus {
        if let override { return override }
        #if DEBUG
        if let forced = DebugLaunch.nlSearchStatus { return forced }
        #endif
        guard #available(iOS 26.0, *) else { return .unavailable }
        #if canImport(FoundationModels)
        return SuggestionAvailability.mapSystemAvailability()
        #else
        return .unavailable
        #endif
    }
}

@MainActor
enum NLSearchParserFactory {
    static func make() -> (any NLSearchParsing)? {
        #if DEBUG
        if let stub = DebugLaunch.nlSearchStub { return stub }
        #endif
        if #available(iOS 26.0, *) {
            #if canImport(FoundationModels)
            return OnDeviceNLSearchParser()
            #endif
        }
        return nil
    }
}

#if canImport(FoundationModels)
/// Guided-generation shape (shared schema `nl-search-filter-schema.md`).
/// Enums keep genres, categories, kind, and watched to catalog vocabulary;
/// `NLSearch.validated` still checks everything before `apply`.
@available(iOS 26.0, *)
@Generable
struct NLSearchFilterDraft {
    @Guide(description: "Title words only, no genre, year, or service. Omit when the question names no title.")
    var title: String?

    @Guide(description: "movie only if the question says movie(s) or film(s). episode only if it says episode(s) or is an S#E# or season/episode request. Otherwise omit.")
    var kind: Kind?

    @Guide(description: "Inclusive start year, 1880...2100. 80s means 1980.")
    var yearMin: Int?
    @Guide(description: "Inclusive end year, 1880...2100. 80s means 1989.")
    var yearMax: Int?

    @Guide(description: "One catalog genre, only if named.")
    var genre: Genre?
    @Guide(description: "One wheel category, only if named.")
    var category: Category?

    @Guide(description: "Short streaming or free service name the question names, e.g. Shudder, Tubi, Netflix.")
    var provider: String?
    @Guide(description: "true only if the question asks for free.")
    var freeOnly: Bool?

    @Guide(description: "Minimum user rating in stars, 0.5...5.")
    var ratingMin: Double?
    @Guide(description: "Maximum user rating in stars, 0.5...5.")
    var ratingMax: Double?
    @Guide(description: "unrated or rated, only if the question asks.")
    var rated: Rated?

    @Guide(description: "Watched status, only if the question asks.")
    var watched: Watched?

    var season: Int?
    var episode: Int?

    @Guide(description: "true only if the question says on my services.")
    var onMyServices: Bool?

    @Generable enum Kind { case movie, episode, any }
    @Generable enum Genre { case drama, horror, sciFi, comedy, thriller, fantasy, action, romance, musical, western }
    @Generable enum Category { case horror, cult, sciFi, prestige, action, darkComedy, criterion, escape, loveHurts, listeners }
    @Generable enum Rated { case unrated, rated }
    @Generable enum Watched { case watched, unwatched, watchlist, any }

    var filter: NLSearchFilter {
        NLSearchFilter(
            title: title,
            kind: kind.map {
                switch $0 {
                case .movie: return .movie
                case .episode: return .episode
                case .any: return .any
                }
            },
            yearMin: yearMin,
            yearMax: yearMax,
            genre: genre.map {
                switch $0 {
                case .drama: return "Drama"
                case .horror: return "Horror"
                case .sciFi: return "Sci-Fi"
                case .comedy: return "Comedy"
                case .thriller: return "Thriller"
                case .fantasy: return "Fantasy"
                case .action: return "Action"
                case .romance: return "Romance"
                case .musical: return "Musical"
                case .western: return "Western"
                }
            },
            category: category.map {
                switch $0 {
                case .horror: return "Horror"
                case .cult: return "Cult"
                case .sciFi: return "Sci-Fi"
                case .prestige: return "Prestige"
                case .action: return "Action"
                case .darkComedy: return "Dark Comedy"
                case .criterion: return "Criterion"
                case .escape: return "Escape"
                case .loveHurts: return "Love Hurts"
                case .listeners: return "Listeners"
                }
            },
            provider: provider,
            freeOnly: freeOnly,
            ratingMin: ratingMin,
            ratingMax: ratingMax,
            unrated: rated.map { $0 == .unrated },
            watched: watched.map {
                switch $0 {
                case .watched: return .watched
                case .unwatched: return .unwatched
                case .watchlist: return .watchlist
                case .any: return .any
                }
            },
            season: season,
            episode: episode,
            onMyServices: onMyServices
        )
    }
}

/// On-device only (`SystemLanguageModel.default`); never Private Cloud
/// Compute. A fresh session per question keeps the context small.
@available(iOS 26.0, *)
struct OnDeviceNLSearchParser: NLSearchParsing {
    static let instructions = """
    Turn a question about the Movie Roulette Tuesday podcast's movie and episode lists into search filters. \
    Fill only fields the question states; omit everything else. Never guess a genre, year, or kind from a title. \
    "80s" means 1980 to 1989. "haven't watched" or "haven't seen" means unwatched. \
    Categories: Horror, Cult, Sci-Fi, Prestige (Prestige Drama), Action, Dark Comedy, Criterion, Escape, Love Hurts, Listeners (Listener Picks). \
    Criterion alone is the category, not Criterion Channel. Max means HBO Max. There is no host filter.
    """

    func prewarm() {
        LanguageModelSession(model: SystemLanguageModel.default, instructions: Self.instructions).prewarm()
    }

    func parse(_ question: String) async throws -> NLSearchFilter {
        let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: Self.instructions)
        let response = try await session.respond(
            to: question,
            generating: NLSearchFilterDraft.self,
            options: GenerationOptions(samplingMode: .greedy)
        )
        return response.content.filter
    }
}
#endif
