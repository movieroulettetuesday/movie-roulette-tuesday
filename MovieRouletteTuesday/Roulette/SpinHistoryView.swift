import SwiftUI
import MRTCore
import MRTShared

/// Local spin log, newest first.
struct SpinHistoryView: View {
    let history: SpinHistoryStore
    let catalog: MovieCatalog?
    var episodesByGUID: [String: PodcastEpisode] = [:]
    var showArtworkURL: URL? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var confirmingClear = false

    var body: some View {
        let stats = history.stats
        NavigationStack {
            Group {
                if history.results.isEmpty {
                    ContentUnavailableView(
                        "No Spins Yet",
                        image: "roulette.wheel",
                        description: Text("Your spins will be listed here.")
                    )
                } else {
                    List {
                        Section {
                            ForEach(history.results.reversed()) { result in
                                // Episode page, else movie page; no link (and no
                                // chevron) when the movie is no longer in the catalog.
                                if let route = SpinHistoryRouting.destination(
                                    for: result, catalog: catalog, episodesByGUID: episodesByGUID
                                ) {
                                    NavigationLink(value: route) {
                                        row(for: result, stats: stats)
                                    }
                                    .accessibilityIdentifier("history-row")
                                } else {
                                    row(for: result, stats: stats)
                                }
                            }
                        } header: {
                            Text("\(stats.totalSpins) spins · \(stats.distinctMoviesSpun) different movies")
                        } footer: {
                            Text(history.lastError ?? footerText)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .cleanProListScreen()
            .navigationDestination(for: MoviesRoute.self) { destination(for: $0, stats: stats) }
            .navigationTitle("Spin History")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear", role: .destructive) { confirmingClear = true }
                        .disabled(history.results.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Clear all spin history on this device?",
                isPresented: $confirmingClear,
                titleVisibility: .visible
            ) {
                Button("Clear history", role: .destructive) { history.clear() }
            }
        }
    }

    @ViewBuilder
    private func destination(for route: MoviesRoute, stats: SpinStats) -> some View {
        switch route {
        case .episode(let guid):
            if let episode = episodesByGUID[guid] {
                // Same page as the Episodes tab.
                EpisodeDetailView(
                    episode: episode,
                    catalog: catalog,
                    show: catalog?.showInfo ?? .mrt,
                    showArtworkURL: showArtworkURL
                )
            } else {
                ContentUnavailableView("Episode Not Found", systemImage: "mic.slash")
            }
        case .movie(let id):
            if let movie = catalog?.movie(withId: id) {
                MoviePageView(
                    movie: movie,
                    catalog: catalog,
                    episodesByGUID: episodesByGUID,
                    showArtworkURL: showArtworkURL,
                    context: .spinHistory
                )
            } else {
                ContentUnavailableView("Movie Not Found", systemImage: "film")
            }
        }
    }

    private var footerText: String {
        if history.archive.totalSpins > 0 {
            return "Showing your latest \(history.results.count) spins; older spins still count toward totals."
        }
        return ""
    }

    private func row(for result: SpinResult, stats: SpinStats) -> some View {
        let movie = catalog?.movie(withId: result.movieId)
        let category = catalog?.category(withId: result.categoryId)
        return HStack(spacing: 12) {
            Circle()
                .fill(CleanPro.category(category))
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(movie?.title ?? result.movieId)
                    .font(.body.weight(.semibold))
                Text(category?.displayName ?? result.categoryId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(result.timestamp, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("×\(stats.spinCount(forMovie: result.movieId))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    SpinHistoryView(history: SpinHistoryStore(fileStore: nil), catalog: nil)
}
