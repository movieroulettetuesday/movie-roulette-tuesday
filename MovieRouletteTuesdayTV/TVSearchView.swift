import SwiftUI
import MRTCore
import MRTShared

/// Search tab (1.1): the system tvOS search field (`.searchable`, the Siri
/// Remote keyboard and dictation) over movies and episodes, using the shared
/// `CatalogSearch` matcher. It replaces the Movies tab's own text field, so
/// there is one keyboard. Results open the existing movie and episode pages.
struct TVSearchView: View {
    let catalog: MovieCatalog?
    let episodes: EpisodeStore
    @Binding var query: String
    var onOpenMovie: (Movie) -> Void
    var onOpenEpisode: (PodcastEpisode) -> Void

    @Environment(\.colorScheme) private var scheme
    private var theme: TVTheme { TVTheme(scheme: scheme) }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 24), count: 4)

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var movieHits: [Movie] {
        guard let catalog, !trimmed.isEmpty else { return [] }
        return CatalogSearch.movies(catalog.movies, matching: trimmed, catalog: catalog, episodesByGUID: episodes.episodesByGUID)
            .map(\.movie)
    }

    private var episodeHits: [PodcastEpisode] {
        guard !trimmed.isEmpty else { return [] }
        return CatalogSearch.episodes(episodes.episodes, matching: trimmed, catalog: catalog).map(\.episode)
    }

    var body: some View {
        NavigationStack {
            results
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .searchable(text: $query, prompt: Text("Movies and episodes"))
        }
        .accessibilityIdentifier("tv.screen.search")
    }

    @ViewBuilder
    private var results: some View {
        let movies = movieHits
        let shows = episodeHits
        if trimmed.isEmpty {
            TVStatusView(
                title: "Search Movie Roulette",
                systemImage: "magnifyingglass",
                message: "Find a movie or an episode by title, year, S4E39, genre, or streaming service."
            )
            .accessibilityIdentifier("tv.search.prompt")
        } else if movies.isEmpty && shows.isEmpty {
            TVStatusView(
                title: "No Matches",
                systemImage: "magnifyingglass",
                message: episodes.episodes.isEmpty
                    ? "Nothing matches “\(trimmed)”. Episodes appear here once the show’s feed has loaded."
                    : "Nothing matches “\(trimmed)”."
            )
            .accessibilityIdentifier("tv.search.empty")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if !movies.isEmpty {
                        sectionTitle("Movies", count: movies.count)
                            .accessibilityIdentifier("tv.search.movies")
                        LazyVGrid(columns: columns, spacing: 24) {
                            ForEach(movies) { movie in
                                Button { onOpenMovie(movie) } label: {
                                    TVMovieCard(movie: movie, catalog: catalog)
                                }
                                .buttonStyle(TVPlainButtonStyle())
                                .accessibilityIdentifier("tv.search.movie.\(movie.id)")
                            }
                        }
                    }
                    if !shows.isEmpty {
                        sectionTitle("Episodes", count: shows.count)
                            .accessibilityIdentifier("tv.search.episodes")
                        LazyVStack(spacing: 16) {
                            ForEach(shows) { episode in
                                Button { onOpenEpisode(episode) } label: { row(episode) }
                                    .buttonStyle(TVRowButtonStyle())
                                    .accessibilityIdentifier("tv.search.episode.\(episode.guid)")
                            }
                        }
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 24)
            }
        }
    }

    private func sectionTitle(_ title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(theme.text)
            Text(count == 1 ? "1 result" : "\(count) results")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(theme.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func row(_ episode: PodcastEpisode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(TVFormat.episodeMeta(episode))
                .font(.system(size: 26, weight: .medium))
                .lineLimit(1)
            Text(episode.title)
                .font(.system(size: 36, weight: .bold))
                .lineLimit(2)
            if let movie = catalog?.movie(forEpisodeGuid: episode.guid) {
                Text(verbatim: "\(movie.title) · \(movie.year)")
                    .font(.system(size: 26))
                    .lineLimit(1)
            }
        }
    }
}
