import Foundation

/// Where a Where-to-Watch chip should go. Same provider table as tvOS
/// `TVProviderLaunching`: a search deep link when we know one, then the
/// provider's https search, then the movie's TMDB watch page.
///
/// Bare schemes that do not carry a search (`videos://`, `disneyplus://`,
/// `hulu://`) are left out. On iOS those apps are usually installed, so
/// trying them first would skip the search page.
public enum ProviderLaunching {
    /// Custom schemes a tap may pass to `canOpenURL`. Keep this equal to
    /// `LSApplicationQueriesSchemes` — only schemes this type actually builds.
    public static let queriedSchemes = ["aiv", "nflx", "youtube"]

    public struct Destination: Equatable, Sendable {
        public var urls: [URL]
        public var appName: String
        public var hint: String

        /// Custom-scheme search, when this provider has one.
        public var appURL: URL? { urls.first { !ProviderLaunching.isWeb($0) } }

        /// First https page (the provider search, or the TMDB watch link).
        public var webURL: URL? { urls.first { ProviderLaunching.isWeb($0) } }

        /// URLs a tap should try. Custom schemes stay only when `canOpen` is true,
        /// so a missing app falls through to the web page instead of an error.
        public func attempts(canOpen: (URL) -> Bool) -> [URL] {
            urls.filter { ProviderLaunching.isWeb($0) || canOpen($0) }
        }
    }

    public static func destination(for provider: StreamingInfo.Provider, movie: Movie) -> Destination {
        let title = movie.title
        let kind = kind(of: provider)
        var apps: [URL] = []
        var web: [URL] = []
        func addApp(_ url: URL?) { if let url, !apps.contains(url) { apps.append(url) } }
        func addWeb(_ url: URL?) { if let url, !web.contains(url) { web.append(url) } }

        switch kind {
        case .netflix:
            addApp(app(scheme: "nflx", host: "www.netflix.com", path: "/search", query: "q", value: title))
            addWeb(page("https://www.netflix.com/search", query: "q", value: title))
        case .prime:
            addApp(app(scheme: "aiv", host: "aiv", path: "/search", query: "query", value: title))
            addWeb(page("https://app.primevideo.com/search", query: "phrase", value: title))
            addWeb(page("https://www.amazon.com/s", items: [
                URLQueryItem(name: "i", value: "instant-video"),
                URLQueryItem(name: "k", value: title),
            ]))
        case .max:
            addWeb(page("https://play.max.com/search", query: "q", value: title))
        case .apple:
            addWeb(page("https://tv.apple.com/us/search", query: "term", value: title))
        case .disney:
            addWeb(page("https://www.disneyplus.com/search", query: "q", value: title))
        case .hulu:
            addWeb(page("https://www.hulu.com/search", query: "q", value: title))
        case .paramount:
            addWeb(page("https://www.paramountplus.com/search/", query: "q", value: title))
        case .peacock:
            addWeb(page("https://www.peacocktv.com/search", query: "q", value: title))
        case .tubi:
            addWeb(tubiSearch(title))
        case .criterion:
            addWeb(page("https://www.criterionchannel.com/search", query: "q", value: title))
        case .youtube:
            addApp(app(scheme: "youtube", host: "www.youtube.com", path: "/results", query: "search_query", value: title))
            addWeb(page("https://www.youtube.com/results", query: "search_query", value: title))
        case .mubi:
            addWeb(page("https://mubi.com/en/search/films", query: "query", value: title))
        case .pluto:
            addWeb(page("https://pluto.tv/search", query: "q", value: title))
        case .shudder:
            addWeb(page("https://www.shudder.com/search", query: "q", value: title))
        case .tcm:
            addWeb(page("https://www.tcm.com/search", query: "q", value: title))
        case .other:
            break
        }

        if apps.isEmpty && web.isEmpty, let link = WhereToWatchDisplay(movie: movie).link {
            addWeb(link)
        }

        let urls = apps + web
        let appName = appName(kind, provider: provider)
        return Destination(
            urls: urls,
            appName: appName,
            hint: hint(appName: appName, providerName: provider.name, urls: urls)
        )
    }

    private enum Kind {
        case netflix, prime, max, apple, disney, hulu, paramount, peacock
        case tubi, criterion, youtube, mubi, pluto, shudder, tcm, other
    }

    /// TMDB ids first, then the name. "Apple" matches a leading "apple" so
    /// another brand's storefront ("AMC Plus Apple TV channel") stays a
    /// TMDB fallback. YouTube TV is not the YouTube app.
    private static func kind(of provider: StreamingInfo.Provider) -> Kind {
        let name = provider.name.lowercased()
        let id = provider.id
        if id == 8 || name.contains("netflix") { return .netflix }
        if id == 9 || id == 10 || name.contains("prime") || name.contains("amazon video") || name == "amazon" {
            return .prime
        }
        if id == 1899 || id == 384 || name == "max" || name.contains("hbo") { return .max }
        if id == 2 || id == 350 || name.hasPrefix("apple") { return .apple }
        if id == 337 || name.contains("disney") { return .disney }
        if id == 15 || name.contains("hulu") { return .hulu }
        if id == 531 || name.contains("paramount") { return .paramount }
        if id == 386 || id == 387 || name.contains("peacock") { return .peacock }
        if id == 73 || name.contains("tubi") { return .tubi }
        if id == 258 || name.contains("criterion") { return .criterion }
        if id == 192 || (name.contains("youtube") && !name.contains("youtube tv")) { return .youtube }
        if id == 11 || name.contains("mubi") { return .mubi }
        if id == 300 || name.contains("pluto") { return .pluto }
        if id == 99 || name.contains("shudder") { return .shudder }
        if id == 361 || name.contains("tcm") { return .tcm }
        return .other
    }

    private static func shortName(_ kind: Kind, provider: StreamingInfo.Provider) -> String {
        switch kind {
        case .netflix: return "Netflix"
        case .prime: return "Prime"
        case .max: return "Max"
        case .apple: return "Apple"
        case .disney: return "Disney+"
        case .hulu: return "Hulu"
        case .paramount: return "Paramount+"
        case .peacock: return "Peacock"
        case .tubi: return "tubi"
        case .criterion: return "Criterion"
        case .youtube: return "YouTube"
        case .mubi: return "MUBI"
        case .pluto: return "Pluto"
        case .shudder: return "Shudder"
        case .tcm: return "TCM"
        case .other: return provider.name
        }
    }

    private static func appName(_ kind: Kind, provider: StreamingInfo.Provider) -> String {
        switch kind {
        case .tubi: return "Tubi"
        case .prime: return "Prime Video"
        case .apple: return "Apple TV"
        case .other: return provider.name
        default: return shortName(kind, provider: provider)
        }
    }

    private static func hint(appName: String, providerName: String, urls: [URL]) -> String {
        let hasApp = urls.contains { !isWeb($0) }
        let hasSite = urls.contains { isWeb($0) && !isTMDB($0) }
        if hasApp && hasSite { return "Opens the \(appName) app or website" }
        if hasApp { return "Opens the \(appName) app" }
        if hasSite { return "Opens \(appName) on the web" }
        if urls.contains(where: isTMDB) { return "Opens all options on TMDB" }
        return "No link for \(providerName)"
    }

    private static func isWeb(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "https" || scheme == "http"
    }

    private static func isTMDB(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "www.themoviedb.org" || host == "themoviedb.org"
    }

    private static func app(scheme: String, host: String, path: String, query name: String, value: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = path.hasPrefix("/") ? path : "/" + path
        components.queryItems = [URLQueryItem(name: name, value: value)]
        return components.url
    }

    private static func page(_ string: String, query name: String, value: String) -> URL? {
        page(string, items: [URLQueryItem(name: name, value: value)])
    }

    private static func page(_ string: String, items: [URLQueryItem]) -> URL? {
        var components = URLComponents(string: string)
        components?.queryItems = items
        return components?.url
    }

    private static func tubiSearch(_ title: String) -> URL? {
        let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
        return URL(string: "https://tubitv.com/search/" + encoded)
    }
}
