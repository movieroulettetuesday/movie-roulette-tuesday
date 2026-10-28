import SwiftUI
import MRTCore
import MRTShared

/// Top tab bar: Roulette · Episodes · Movies · Stats.
/// Detail screens replace the tab bar (mockups 06, 08, 10). Suggest is a card on top.
struct TVRootView: View {
    enum Tab: Hashable { case roulette, episodes, movies, stats }

    enum Page: Hashable {
        case episode(String)
        case movie(String, breadcrumb: String)
        case settings
    }

    let roulette: RouletteViewModel
    let episodes: EpisodeStore

    @Environment(CommunityService.self) private var community
    @State private var tab: Tab
    @State private var pages: [Page]
    @State private var showsSuggest: Bool

    init(roulette: RouletteViewModel, episodes: EpisodeStore) {
        self.roulette = roulette
        self.episodes = episodes
        let args = ProcessInfo.processInfo.arguments
        _tab = State(initialValue: Self.tab(from: args))
        _pages = State(initialValue: Self.pages(from: args))
        _showsSuggest = State(initialValue: args.contains("-MRTShowSuggest"))
    }

    var body: some View {
        ZStack {
            TVBackground()
            if showsSuggest {
                TVSuggestView(url: TVSuggestView.fanMailURL(in: episodes.episodes)) {
                    showsSuggest = false
                }
            } else if let page = pages.last {
                detail(page)
            } else {
                tabs
            }
        }
        .onOpenURL(perform: open)
        .onChange(of: AppRouter.shared.pendingURL) { _, url in
            if let url { open(url) }
        }
        .task {
            if let url = AppRouter.shared.pendingURL { open(url) }
            await roulette.load()
            await roulette.refreshRemoteCatalog()
            await episodes.load()
            await community.refreshAccountStatus()
            if tab == .episodes { episodes.markViewed() }
        }
        .onChange(of: roulette.catalog?.movies.count) { _, _ in
            let ids = roulette.catalog?.movies.map(\.id) ?? []
            Task { await community.refreshAllListenerRatings(movieIds: ids) }
        }
        .onChange(of: tab) { _, new in
            if new == .episodes { episodes.markViewed() }
        }
        .onChange(of: episodes.episodes.count) { _, _ in
            if tab == .episodes, pages.isEmpty { episodes.markViewed() }
        }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            TVRouletteView(model: roulette) { openMovie($0, breadcrumb: "Tonight's Movie") }
                .tabItem { Text("Roulette") }
                .tag(Tab.roulette)
            TVEpisodesView(store: episodes, catalog: roulette.catalog) { episode in
                pages.append(.episode(episode.guid))
            }
            .tabItem { Text("Episodes") }
            .tag(Tab.episodes)
            TVMoviesView(
                catalog: roulette.catalog,
                loadState: roulette.loadState,
                history: roulette.history,
                episodesByGUID: episodes.episodesByGUID,
                showArtworkURL: episodes.showArtworkURL,
                onOpen: { openMovie($0, breadcrumb: "Movies") },
                onRetry: { Task { await roulette.load() } }
            )
            .tabItem { Text("Movies") }
            .tag(Tab.movies)
            TVStatsView(
                history: roulette.history,
                catalog: roulette.catalog,
                onOpenMovie: { openMovie($0, breadcrumb: "Stats") },
                onSettings: { pages.append(.settings) }
            )
            .tabItem { Text("Stats") }
            .tag(Tab.stats)
        }
        .overlay(alignment: .top) {
            if episodeBadgeCount > 0 {
                TVEpisodesTabDot()
            }
        }
    }

    /// Unseen episodes, or 1 while this week's episode is still recent (the tab dot).
    private var episodeBadgeCount: Int {
        max(episodes.newEpisodeCount, TVFormat.newestIsRecent(episodes.episodes) ? 1 : 0)
    }

    @ViewBuilder
    private func detail(_ page: Page) -> some View {
        switch page {
        case .episode(let guid):
            if let episode = episodes.episode(guid: guid) {
                TVEpisodeDetailView(
                    episode: episode,
                    catalog: roulette.catalog,
                    showArtworkURL: episodes.showArtworkURL,
                    showsNew: TVFormat.showsNewBadge(episode, in: episodes.episodes),
                    onOpenMovie: { openMovie($0, breadcrumb: "Episodes") },
                    onBack: pop
                )
            } else if case .failed(let message) = episodes.loadState, episodes.episodes.isEmpty {
                TVStatusView(
                    title: "Episode Not Available",
                    systemImage: "mic.slash",
                    message: message,
                    retryTitle: "Try again",
                    retry: { Task { await episodes.load(forceNetwork: true) } }
                )
            } else {
                TVStatusView(title: "Loading episode…", systemImage: "mic")
                    .task { await episodes.load() }
            }
        case .movie(let id, let breadcrumb):
            if let movie = roulette.catalog?.movie(withId: id) {
                TVMoviePageView(
                    movie: movie,
                    catalog: roulette.catalog,
                    episodesByGUID: episodes.episodesByGUID,
                    breadcrumb: breadcrumb,
                    onSuggest: { showsSuggest = true },
                    onBack: pop
                )
            } else if case .failed(let message) = roulette.loadState {
                TVStatusView(
                    title: "Movie Not Available",
                    systemImage: "film",
                    message: message,
                    retryTitle: "Try again",
                    retry: { Task { await roulette.load() } }
                )
            } else {
                TVStatusView(title: "Loading movie…", systemImage: "film")
                    .task { await roulette.load() }
            }
        case .settings:
            TVSettingsView(onSuggest: { showsSuggest = true }, onBack: pop)
        }
    }

    private func openMovie(_ movie: Movie, breadcrumb: String) {
        pages.append(.movie(movie.id, breadcrumb: breadcrumb))
    }

    private func pop() {
        if !pages.isEmpty { pages.removeLast() }
    }

    private func open(_ url: URL) {
        guard let link = DeepLink(url: url) else { return }
        showsSuggest = false
        switch link {
        case .movie(let id):
            pages = [.movie(id, breadcrumb: "Movies")]
        case .episode(let guid):
            pages = [.episode(guid)]
        }
        AppRouter.shared.pendingURL = nil
    }

    private static func tab(from args: [String]) -> Tab {
        guard let index = args.firstIndex(of: "-MRTStartTab"), args.indices.contains(index + 1) else { return .roulette }
        switch args[index + 1].lowercased() {
        case "episodes": return .episodes
        case "movies": return .movies
        case "stats": return .stats
        default: return .roulette
        }
    }

    private static func pages(from args: [String]) -> [Page] {
        if let index = args.firstIndex(of: "-MRTOpenMovie"), args.indices.contains(index + 1) {
            return [.movie(args[index + 1], breadcrumb: "Movies")]
        }
        if let index = args.firstIndex(of: "-MRTOpenEpisode"), args.indices.contains(index + 1) {
            return [.episode(args[index + 1])]
        }
        return []
    }
}
