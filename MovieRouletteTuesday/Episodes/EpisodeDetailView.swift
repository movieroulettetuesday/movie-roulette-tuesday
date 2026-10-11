import SwiftUI

struct EpisodeDetailView: View {
    let episode: PodcastEpisode
    let catalog: MovieCatalog?
    let show: ShowInfo
    var showArtworkURL: URL? = nil
    /// Off when this page was pushed from a movie page, so the two pages
    /// can't push each other forever (back already returns to the movie).
    var showsFilmLink = true

    @Environment(CommunityService.self) private var community

    private var movie: Movie? { catalog?.movie(forEpisodeGuid: episode.guid) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CleanPro.spacing) {
                header

                if !episode.summary.isEmpty {
                    CleanProSection("About") {
                        Text(episode.summary)
                    }
                }

                if showsFilmLink, let movie {
                    CleanProSection("Film Discussed") {
                        NavigationLink {
                            MoviePageView(
                                movie: movie,
                                catalog: catalog,
                                spinCount: 0,
                                episodesByGUID: [episode.guid: episode],
                                showArtworkURL: showArtworkURL
                            )
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(movie.title).font(.body.weight(.semibold))
                                    Text(verbatim: "\(movie.year) · \(movie.genre)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                EpisodePollSection(poll: community.poll(forEpisode: episode.guid, show: show))

                ListenCard(episode: episode, show: show)

                CleanProSection("Episode ID") {
                    Text(episode.guid)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background { CleanProBackground() }
        .accessibilityIdentifier("episode-detail")
        .navigationTitle(episode.seasonEpisodeLabel ?? "Episode")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(spacing: 16) {
            ArtworkImage(
                urls: ArtworkResolver.candidates(for: episode, showArtwork: showArtworkURL),
                pointSize: 220,
                cornerRadius: 22,
                placeholderSymbol: "mic"
            )
            .frame(width: 220, height: 220)
            .shadow(color: .black.opacity(0.10), radius: 3, y: 2)
            .shadow(color: .black.opacity(0.20), radius: 18, y: 10)
            .accessibilityIdentifier("episode-artwork")

            VStack(spacing: 6) {
                Text(episode.title)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                HStack(spacing: 8) {
                    if let se = episode.seasonEpisodeLabel {
                        Text(se).fontWeight(.semibold)
                    }
                    if let date = episode.pubDate {
                        Text(date, format: .dateTime.month(.abbreviated).day().year())
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }
}
