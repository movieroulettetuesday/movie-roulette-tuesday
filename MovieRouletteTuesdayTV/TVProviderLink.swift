import SwiftUI
import MRTCore
import MRTShared

/// Where-to-watch tiles try the provider's app, then a search page on the web.
/// tvOS hands many of these https links to the installed app.
enum TVProviderLaunching {
    struct Launch {
        var shortName: String
        var appName: String
        var hint: String
        var background: Color
        var foreground: Color
        var urls: [URL]
    }

    /// Stream and free first (the result screen), then rent/buy when the movie page asks.
    static func tiles(for movie: Movie, includeRentals: Bool, limit: Int = 6) -> [StreamingInfo.Provider] {
        guard let streaming = movie.streaming else { return [] }
        var seen = Set<Int>()
        let groups = includeRentals
            ? streaming.stream + streaming.free + StreamingCatalog.rentOrBuy(streaming)
            : streaming.stream + streaming.free
        let ordered = groups.sorted { ($0.priority ?? .max) < ($1.priority ?? .max) }
        return Array(ordered.filter { seen.insert($0.id).inserted }.prefix(limit))
    }

    static func launch(for provider: StreamingInfo.Provider, movie: Movie) -> Launch {
        let kind = kind(of: provider)
        let title = movie.title
        var urls: [URL] = []
        func add(_ url: URL?) { if let url, !urls.contains(url) { urls.append(url) } }
        switch kind {
        case .netflix:
            add(url("https://www.netflix.com/search", query: "q", value: title))
            add(URL(string: "nflx://www.netflix.com/search?q=\(encoded(title))"))
        case .prime:
            add(url("https://app.primevideo.com/search", query: "phrase", value: title))
            add(url("https://www.amazon.com/s", items: [
                URLQueryItem(name: "i", value: "instant-video"),
                URLQueryItem(name: "k", value: title),
            ]))
            add(URL(string: "aiv://aiv/search?query=\(encoded(title))"))
        case .max:
            add(url("https://play.max.com/search", query: "q", value: title))
        case .apple:
            add(url("https://tv.apple.com/us/search", query: "term", value: title))
            add(URL(string: "videos://"))
        case .disney:
            add(url("https://www.disneyplus.com/search", query: "q", value: title))
            add(URL(string: "disneyplus://"))
        case .hulu:
            add(url("https://www.hulu.com/search", query: "q", value: title))
            add(URL(string: "hulu://"))
        case .paramount:
            add(url("https://www.paramountplus.com/search/", query: "q", value: title))
        case .peacock:
            add(url("https://www.peacocktv.com/search", query: "q", value: title))
        case .tubi:
            add(URL(string: "https://tubitv.com/search/\(encoded(title))"))
        case .criterion:
            add(url("https://www.criterionchannel.com/search", query: "q", value: title))
        case .youtube:
            add(url("https://www.youtube.com/results", query: "search_query", value: title))
            add(URL(string: "youtube://www.youtube.com/results?search_query=\(encoded(title))"))
        case .mubi:
            add(url("https://mubi.com/en/search/films", query: "query", value: title))
        case .pluto:
            add(url("https://pluto.tv/search", query: "q", value: title))
        case .shudder:
            add(url("https://www.shudder.com/search", query: "q", value: title))
        case .tcm:
            add(url("https://www.tcm.com/search", query: "q", value: title))
        case .other:
            break
        }
        if urls.isEmpty, let link = WhereToWatchDisplay(movie: movie).link { add(link) }
        let app = appName(kind, provider: provider)
        let hint = urls.isEmpty ? "No app link for \(provider.name)" : "Opens the \(app) app"
        let colors = tileColors(kind)
        return Launch(
            shortName: shortName(kind, provider: provider),
            appName: app,
            hint: hint,
            background: colors.background,
            foreground: colors.foreground,
            urls: urls
        )
    }

    private enum Kind {
        case netflix, prime, max, apple, disney, hulu, paramount, peacock
        case tubi, criterion, youtube, mubi, pluto, shudder, tcm, other
    }

    private static func kind(of provider: StreamingInfo.Provider) -> Kind {
        let name = provider.name.lowercased()
        let id = provider.id
        if id == 8 || name.contains("netflix") { return .netflix }
        if id == 9 || id == 10 || name.contains("prime") || name.contains("amazon video") || name == "amazon" {
            return .prime
        }
        if id == 1899 || id == 384 || name == "max" || name.contains("hbo") { return .max }
        if id == 2 || id == 350 || name.contains("apple") { return .apple }
        if id == 337 || name.contains("disney") { return .disney }
        if id == 15 || name.contains("hulu") { return .hulu }
        if id == 531 || name.contains("paramount") { return .paramount }
        if id == 386 || id == 387 || name.contains("peacock") { return .peacock }
        if id == 73 || name.contains("tubi") { return .tubi }
        if id == 258 || name.contains("criterion") { return .criterion }
        if id == 192 || name.contains("youtube") { return .youtube }
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

    private static func tileColors(_ kind: Kind) -> (background: Color, foreground: Color) {
        switch kind {
        case .max: return (Color(hex: "#5B2BE0"), .white)
        case .tubi: return (Color(hex: "#F26B21"), .white)
        case .criterion: return (Color(hex: "#1A1A1A"), .white)
        case .prime: return (Color(hex: "#1CA8E0"), .white)
        case .apple: return (.white, Color(hex: "#111111"))
        case .netflix: return (Color(hex: "#E50914"), .white)
        case .disney: return (Color(hex: "#113CCF"), .white)
        case .hulu: return (Color(hex: "#1CE783"), Color(hex: "#0B1C12"))
        case .youtube: return (Color(hex: "#FF0033"), .white)
        case .paramount: return (Color(hex: "#0064FF"), .white)
        case .peacock: return (Color(hex: "#000000"), .white)
        default: return (Color(hex: "#2E393C"), .white)
        }
    }

    private static func encoded(_ title: String) -> String {
        title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
    }

    private static func url(_ string: String, query name: String, value: String) -> URL? {
        url(string, items: [URLQueryItem(name: name, value: value)])
    }

    private static func url(_ string: String, items: [URLQueryItem]) -> URL? {
        var components = URLComponents(string: string)
        components?.queryItems = items
        return components?.url
    }
}

struct TVProviderButton: View {
    let provider: StreamingInfo.Provider
    let movie: Movie
    var side: CGFloat = 132
    var onOpen: (TVProviderLaunching.Launch) -> Void

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        let launch = TVProviderLaunching.launch(for: provider, movie: movie)
        Button { onOpen(launch) } label: {
            Text(launch.shortName)
                .font(.system(size: launch.shortName.count > 8 ? 22 : 28, weight: .heavy))
                .foregroundStyle(launch.foreground)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
                .lineLimit(2)
                .padding(8)
                .frame(width: side, height: side)
                .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(launch.background))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color.white.opacity(isFocused ? 0.9 : 0.18), lineWidth: isFocused ? 4 : 2)
                )
                .shadow(color: Brand.teal.opacity(isFocused ? 0.75 : 0), radius: isFocused ? 22 : 0)
                .scaleEffect(isFocused ? 1.08 : 1)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
        .buttonStyle(TVPlainButtonStyle())
        .accessibilityLabel(launch.appName)
        .accessibilityHint(launch.hint)
        .accessibilityIdentifier("tv.provider.\(provider.id)")
    }
}
