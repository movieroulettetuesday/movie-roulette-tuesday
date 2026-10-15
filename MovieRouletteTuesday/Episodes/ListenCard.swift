import SwiftUI

/// Episode page "Listen" card (approved v4 mockup).
/// Apple Podcasts: the exact episode once the iTunes lookup matches its GUID
/// (show page until then). Spotify: a search for the episode (Spotify has no
/// public GUID lookup). Overcast: the show. Buzzsprout: the exact episode page.
struct ListenCard: View {
    let episode: PodcastEpisode
    var show: ShowInfo = .mrt
    private var apple: AppleEpisodeLinks { .shared }

    var body: some View {
        CleanProSection("Listen") {
            Group {
                let appleLink = apple.link(forGUID: episode.guid, show: show)
                if let appleLink {
                    row(appleLink.url, "Apple Podcasts",
                        appleLink.isExactEpisode ? "This episode" : "Show page (episode not listed yet)",
                        "apple.logo", "#9B4DE0", id: "listen-apple")
                }
                if let url = PodcastLinks.spotifySearch(episodeTitle: episode.title) ?? PodcastLinks.spotifyShow(show: show) {
                    Divider()
                    row(url, "Spotify", "Search for this episode", "waveform", "#1DB954", id: "listen-spotify")
                }
                if let url = PodcastLinks.overcastShow(show: show) {
                    Divider()
                    row(url, "Overcast", "Show page", "dot.radiowaves.left.and.right", "#FC7E0F", id: "listen-overcast")
                }
                if let url = PodcastLinks.buzzsproutEpisode(guid: episode.guid, show: show) ?? PodcastLinks.buzzsproutShow(show: show) {
                    Divider()
                    row(url, "Buzzsprout", "Episode page", "globe", "#3A9CA6", id: "listen-buzzsprout")
                }
            }
        }
        .task(id: episode.guid) { await apple.ensure(guid: episode.guid, show: show) }
    }

    private func row(_ url: URL, _ title: String, _ detail: String, _ symbol: String, _ hex: String, id: String) -> some View {
        Link(destination: url) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color(hex: hex), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.forward").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(detail)")
        .accessibilityHint("Opens outside the app")
        .accessibilityIdentifier(id)
    }
}
