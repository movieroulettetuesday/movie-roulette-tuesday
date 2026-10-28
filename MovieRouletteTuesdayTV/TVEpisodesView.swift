import SwiftUI
import MRTCore
import MRTShared

/// Episodes tab (mockup 05): newest first, a preview of the focused row on the right.
/// Select opens the detail screen, which hides the tab bar.
struct TVEpisodesView: View {
    let store: EpisodeStore
    let catalog: MovieCatalog?
    var onOpen: (PodcastEpisode) -> Void

    @Environment(\.colorScheme) private var scheme
    @FocusState private var focusedGUID: String?
    @State private var previewGUID: String?

    private var theme: TVTheme { TVTheme(scheme: scheme) }
    private var episodes: [PodcastEpisode] { TVFormat.sortedNewestFirst(store.episodes) }
    private var preview: PodcastEpisode? {
        let guid = previewGUID ?? focusedGUID ?? episodes.first?.guid
        return guid.flatMap { store.episode(guid: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            header
            content
        }
        .padding(.horizontal, 80)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .accessibilityIdentifier("tv.screen.episodes")
        .onChange(of: focusedGUID) { _, guid in
            if let guid { previewGUID = guid }
        }
        .onAppear { TVFocus.soon { focusFirst() } }
        .onChange(of: episodes.first?.guid) { _, _ in
            if focusedGUID == nil { focusFirst() }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            TVScreenTitle(text: "Episodes")
            Spacer()
            Text(seasonLine)
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(theme.secondary)
        }
    }

    private var loadingEpisodes: some View {
        TVStatusView(title: "Loading episodes…", systemImage: "mic", message: nil)
            .accessibilityIdentifier("tv.episodes.loading")
    }

    private var seasonLine: String {
        if let season = episodes.first?.season { return "Season \(season) · Newest first" }
        return "Newest first"
    }

    @ViewBuilder
    private var content: some View {
        switch store.loadState {
        case .idle:
            loadingEpisodes
        case .loading where episodes.isEmpty:
            loadingEpisodes
        case .failed(let message) where episodes.isEmpty:
            TVStatusView(
                title: "Couldn’t Load Episodes",
                systemImage: "wifi.exclamationmark",
                message: message,
                retryTitle: "Try again",
                retry: { Task { await store.load(forceNetwork: true) } }
            )
            .accessibilityIdentifier("tv.episodes.error")
        default:
            if episodes.isEmpty {
                TVStatusView(
                    title: "No Episodes Yet",
                    systemImage: "mic",
                    message: "The show’s feed didn’t include any episodes.",
                    retryTitle: "Try again",
                    retry: { Task { await store.load(forceNetwork: true) } }
                )
                .accessibilityIdentifier("tv.episodes.empty")
            } else {
                listAndPreview
            }
        }
    }

    private var listAndPreview: some View {
        HStack(alignment: .top, spacing: 48) {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if let err = store.lastError {
                        Text(err)
                            .font(.system(size: 26))
                            .foregroundStyle(theme.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(episodes) { episode in
                        Button { onOpen(episode) } label: { row(episode) }
                            .buttonStyle(TVRowButtonStyle())
                            .focused($focusedGUID, equals: episode.guid)
                            .accessibilityIdentifier("tv.episode.\(episode.guid)")
                    }
                }
                .padding(.vertical, 8)
            }
            .focusSection()
            .defaultFocus($focusedGUID, episodes.first?.guid)
            previewPane
                .frame(width: 520)
        }
    }

    private func row(_ episode: PodcastEpisode) -> some View {
        HStack(alignment: .center, spacing: 22) {
            ArtworkImage(
                urls: ArtworkResolver.candidates(for: episode, showArtwork: store.showArtworkURL),
                pointSize: 92,
                cornerRadius: 16,
                placeholderSymbol: "mic"
            )
            .frame(width: 92, height: 92)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    if TVFormat.showsNewBadge(episode, in: episodes) {
                        Text("NEW")
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Brand.tealDark))
                    }
                    Text(TVFormat.episodeMeta(episode))
                        .font(.system(size: 26, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let runtime = TVFormat.runtime(episode.duration) {
                        Text(runtime)
                            .font(.system(size: 26))
                    }
                }
                Text(episode.title)
                    .font(.system(size: 36, weight: .bold))
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var previewPane: some View {
        if let episode = preview {
            VStack(alignment: .leading, spacing: 22) {
                ArtworkImage(
                    urls: ArtworkResolver.candidates(for: episode, showArtwork: store.showArtworkURL),
                    pointSize: 480,
                    cornerRadius: 28,
                    placeholderSymbol: "mic"
                )
                .frame(width: 480, height: 480)
                .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
                Text(episode.displaySummary)
                    .font(.system(size: 28))
                    .foregroundStyle(theme.secondary)
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("tv.episodes.preview")
        }
    }

    private func focusFirst() {
        if focusedGUID == nil { focusedGUID = episodes.first?.guid }
        if previewGUID == nil { previewGUID = episodes.first?.guid }
    }
}
