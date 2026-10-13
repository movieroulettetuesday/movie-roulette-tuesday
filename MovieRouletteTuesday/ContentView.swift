import SwiftUI

struct ContentView: View {
    let roulette: RouletteViewModel
    let episodes: EpisodeStore

    enum Tab: Hashable { case roulette, episodes, movies, stats }
    @State private var selectedTab: Tab = .roulette
    /// Movie id from an `mrt://movie/<id>` link, handed to the Movies tab.
    @State private var pendingMovieID: String?
    @State private var pendingEpisodeGUID: String?
    /// Cold-launch opening; a deep link or widget tap finishes it at once.
    @Environment(SplashState.self) private var splash: SplashState?

    var body: some View {
        TabView(selection: $selectedTab) {
            RouletteView(model: roulette, episodesByGUID: episodes.episodesByGUID, showArtworkURL: episodes.showArtworkURL)
                .tabItem { Label("Roulette", image: "roulette.wheel") }
                .tag(Tab.roulette)

            EpisodesView(store: episodes, catalog: roulette.catalog, pendingEpisodeGUID: $pendingEpisodeGUID)
                .tabItem { Label("Episodes", systemImage: "mic") }
                .tag(Tab.episodes)
                // 0 hides the badge.
                .badge(selectedTab == .episodes ? 0 : episodes.newEpisodeCount)

            MoviesView(
                catalog: roulette.catalog,
                history: roulette.history,
                episodesByGUID: episodes.episodesByGUID,
                episodeStore: episodes,
                pendingMovieID: $pendingMovieID
            )
            .tabItem { Label("Movies", systemImage: "film.stack") }
            .tag(Tab.movies)

            StatsView(history: roulette.history, catalog: roulette.catalog)
                .tabItem { Label("Stats", systemImage: "chart.bar") }
                .tag(Tab.stats)
        }
        #if DEBUG
        .task {
            if let tab = DebugLaunch.startTab { selectedTab = tab }
            if let id = DebugLaunch.openMovieID {
                splash?.skip()
                selectedTab = .movies
                pendingMovieID = id
            }
            try? await Task.sleep(for: .milliseconds(300))
            DebugLaunch.applyRequestedOrientation()
        }
        #endif
        .task {
            // Load the catalog here, not only in RouletteView: a cold-launch deep link
            // (or a Movies-first launch) may never show the Roulette tab.
            await roulette.load()
            // Then (in the background, short timeout) check GitHub for a newer movie list.
            await roulette.refreshRemoteCatalog()
        }
        .task {
            // Warm the episode cache in parallel with roulette's catalog load.
            await episodes.load()
        }
        .onOpenURL { url in handle(url) }
        // Siri "Open in App" and new-episode notification taps.
        .onChange(of: AppRouter.shared.pendingURL, initial: true) { _, url in
            guard let url else { return }
            AppRouter.shared.pendingURL = nil
            handle(url)
        }
        .onChange(of: selectedTab) { oldTab, newTab in
            // Viewing the tab clears the badge; leaving it stamps "seen up to now".
            if newTab == .episodes || oldTab == .episodes { episodes.markViewed() }
        }
        .onChange(of: episodes.lastFetchedAt) { _, _ in
            // New episodes arriving while the tab is on screen count as seen.
            if selectedTab == .episodes { episodes.markViewed() }
            // Pull-to-refresh (and other episode fetches) also re-check the movie list,
            // so a new episode's movie shows up with it. Throttled in the model.
            Task { await roulette.refreshRemoteCatalog() }
            // Episodes already in the app never trigger a new-episode alert later.
            if NewEpisodeAlerts.isEnabled { NewEpisodeAlerts.markSeen(episodes.episodes) }
        }
    }

    private func handle(_ url: URL) {
        #if DEBUG
        FileHandle.standardError.write(Data("MRT-OPENURL \(url.absoluteString)\n".utf8))
        #endif
        // Never land behind the opening animation (widget taps arrive here too).
        splash?.skip()
        guard let link = DeepLink(url: url) else { return }
        // Close the reveal sheet (if any) so the destination is visible.
        if roulette.reveal != nil { roulette.reveal = nil }
        switch link {
        case .movie(let id):
            selectedTab = .movies
            pendingMovieID = id
        case .episode(let guid):
            selectedTab = .episodes
            pendingEpisodeGUID = guid
        }
    }
}

#Preview {
    ContentView(
        roulette: .preview(),
        episodes: EpisodeStore(cacheURL: nil)
    )
    .environment(PersonalRatingsStore(fileStore: nil))
    .environment(CommunityService.preview())
}
