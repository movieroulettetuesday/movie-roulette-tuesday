import SwiftUI

struct EpisodesView: View {
    @Bindable var store: EpisodeStore
    var catalog: MovieCatalog?
    /// Set by a new-episode notification tap (`mrt://episode/<guid>`).
    var pendingEpisodeGUID: Binding<String?> = .constant(nil)

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Split-view selection (regular width).
    @State private var selectedGUID: String?
    /// Stack path (compact width). Synced with `selectedGUID` on size-class changes.
    @State private var path: [String] = []
    @AppStorage("episodes.grouping") private var groupingRaw = EpisodeGrouping.season.rawValue
    @AppStorage("episodes.expandedGroups") private var expansionRaw = ""

    private var grouping: EpisodeGrouping { EpisodeGrouping(rawValue: groupingRaw) ?? .season }

    private var isRegular: Bool { horizontalSizeClass == .regular }

    var body: some View {
        Group {
            if isRegular {
                NavigationSplitView {
                    sidebarContent
                        .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 460)
                } detail: {
                    NavigationStack {
                        if let guid = selectedGUID, let episode = store.episode(guid: guid) {
                            detail(for: episode)
                        } else {
                            ContentUnavailableView(
                                "Pick an Episode",
                                systemImage: "mic",
                                description: Text("Choose an episode to see its details and the listener poll.")
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background { CleanProBackground() }
                        }
                    }
                    .id(selectedGUID)
                }
            } else {
                NavigationStack(path: $path) {
                    sidebarContent
                        .navigationDestination(for: String.self) { guid in
                            if let episode = store.episode(guid: guid) {
                                detail(for: episode)
                            } else {
                                ContentUnavailableView("Episode Not Found", systemImage: "mic.slash")
                            }
                        }
                }
            }
        }
        .onChange(of: pendingEpisodeGUID.wrappedValue, initial: true) { _, guid in
            guard let guid else { return }
            pendingEpisodeGUID.wrappedValue = nil
            selectedGUID = guid
            path = [guid]
        }
        .onChange(of: isRegular) { _, regular in
            if regular {
                selectedGUID = path.last ?? selectedGUID
            } else {
                path = selectedGUID.map { [$0] } ?? []
            }
        }
    }

    private func detail(for episode: PodcastEpisode) -> some View {
        EpisodeDetailView(
            episode: episode,
            catalog: catalog,
            show: catalog?.showInfo ?? .mrt,
            showArtworkURL: store.showArtworkURL
        )
    }

    private var sidebarContent: some View {
        Group {
            switch store.loadState {
            case .idle:
                ProgressView("Loading episodes…")
            case .loading where store.episodes.isEmpty:
                ProgressView("Loading episodes…")
            case .failed(let message) where store.episodes.isEmpty:
                ContentUnavailableView {
                    Label("Couldn't Load Episodes", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await store.load(forceNetwork: true) } }
                }
            default:
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .cleanProListScreen()
        .navigationTitle("Episodes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if case .loaded(fromCache: true) = store.loadState {
                    Text("Offline")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task { await store.load() }
    }

    @ViewBuilder
    private var list: some View {
        Group {
            if isRegular {
                List(selection: $selectedGUID) { listContent }
                    .refreshable { await store.load(forceNetwork: true) }
            } else {
                List { listContent }
                    .refreshable { await store.load(forceNetwork: true) }
            }
        }
        // Outside the List, so the first list cell is still the newest episode.
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("Group episodes by", selection: $groupingRaw) {
                ForEach(EpisodeGrouping.allCases) { Text($0.label).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
            .accessibilityIdentifier("episodes-grouping")
        }
    }

    private func row(_ episode: PodcastEpisode) -> some View {
        NavigationLink(value: episode.guid) {
            EpisodeRow(
                episode: episode,
                movie: catalog?.movie(forEpisodeGuid: episode.guid),
                catalog: catalog,
                showArtworkURL: store.showArtworkURL
            )
        }
        .accessibilityIdentifier("episode-row")
    }

    private func groupHeader(_ group: EpisodeGroup, expanded: Bool, isNewest: Bool) -> some View {
        Button {
            var e = EpisodeGroupExpansion(serialized: expansionRaw)
            e.toggle(group.id, isNewest: isNewest)
            withAnimation(.easeInOut(duration: 0.2)) { expansionRaw = e.serialized }
        } label: {
            HStack {
                Text(group.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(group.episodes.count == 1 ? "1 episode" : "\(group.episodes.count) episodes")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .textCase(nil)
        .accessibilityLabel("\(group.title), \(group.episodes.count) episodes")
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
        .accessibilityHint(expanded ? "Collapses the section" : "Expands the section")
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("episode-group-\(group.id)")
    }

    @ViewBuilder
    private var listContent: some View {
        if let err = store.lastError {
            Section {
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        if grouping == .all {
            Section {
                ForEach(store.episodes) { row($0) }
            } footer: {
                footer
            }
        } else {
            let groups = EpisodeGrouper.groups(store.episodes, by: grouping)
            let expansion = EpisodeGroupExpansion(serialized: expansionRaw)
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                let isNewest = index == 0
                let expanded = expansion.isExpanded(group.id, isNewest: isNewest)
                Section {
                    if expanded {
                        ForEach(group.episodes) { row($0) }
                    }
                } header: {
                    groupHeader(group, expanded: expanded, isNewest: isNewest)
                } footer: {
                    if index == groups.count - 1 { footer }
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            let totals = EpisodeTotals(episodes: store.episodes, catalog: catalog)
            Text("\(totals.feedEpisodes) episodes in the Buzzsprout feed.")
            if catalog != nil {
                Text("\(totals.feedEpisodesWithFilm) discuss a film in the Movies tab; the rest are trailers, bonus or non-movie episodes.")
            }
            if let date = store.lastFetchedAt {
                Text("Updated \(date.formatted(.relative(presentation: .named)))")
            }
        }
    }
}

private struct EpisodeRow: View {
    let episode: PodcastEpisode
    let movie: Movie?
    var catalog: MovieCatalog? = nil
    var showArtworkURL: URL?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ArtworkImage(
                urls: ArtworkResolver.candidates(for: episode, showArtwork: showArtworkURL),
                pointSize: 56,
                cornerRadius: 10,
                placeholderSymbol: "mic"
            )
            .frame(width: 56, height: 56)
            .padding(.top, 2)
            details
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(episode.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 8)
                if let se = episode.seasonEpisodeLabel {
                    Text(se)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            if let date = episode.pubDate {
                Text(date, format: .dateTime.month(.abbreviated).day().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !episode.displaySummary.isEmpty {
                Text(episode.displaySummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let movie {
                Text(verbatim: catalog?.subtitle(for: movie) ?? "\(movie.year) · \(movie.genre)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    EpisodesView(store: EpisodeStore(cacheURL: nil), catalog: nil)
        .environment(PersonalRatingsStore(fileStore: nil))
        .environment(SpinHistoryStore(fileStore: nil))
        .environment(CommunityService.preview())
}
