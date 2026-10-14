import SwiftUI

/// Movie detail — catalog facts, linked episodes, local spin count.
struct MoviePageView: View {
    let movie: Movie
    let catalog: MovieCatalog?
    var episodesByGUID: [String: PodcastEpisode] = [:]
    var showArtworkURL: URL? = nil
    /// When true (Movies tab), episode rows are value links
    /// (`MoviesRoute.episode`) that push the episode page in the same stack.
    /// Other hosts (reveal sheet, Episodes tab) keep plain rows.
    /// Default: the film card inside an episode page (no episode links).
    var context: MoviePageContext = .episodeDetail
    private var linksEpisodes: Bool { context.linksEpisodes }

    @Environment(PersonalRatingsStore.self) private var personal
    /// The app's one spin log (`SpinHistoryStore.shared`, injected at the root).
    /// Read here, not passed in, so every host shows the same live count.
    @Environment(SpinHistoryStore.self) private var history
    private var spinCount: Int { history.stats.spinCount(forMovie: movie.id) }
    @Environment(CommunityService.self) private var community
    @AppStorage(AppSettings.autoShareRatings) private var autoShareRatings = false
    @Environment(\.colorScheme) private var colorScheme

    private var show: ShowInfo { catalog?.showInfo ?? .mrt }
    private var myRating: Int? { personal.halfStars(for: movie.id) }

    private var statusBinding: Binding<WatchStatus?> {
        Binding(
            get: { personal.status(for: movie.id) },
            set: { personal.setStatus($0, for: movie.id) }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CleanPro.spacing) {
                header

                episodesSection

                yourTake

                ListenerRatingSection(movieId: movie.id, myRating: myRating)

                CleanProSection("Categories") {
                    ForEach(movie.categories, id: \.self) { id in
                        let cat = catalog?.category(withId: id)
                        HStack(spacing: 10) {
                            Circle()
                                .fill(CleanPro.category(cat))
                                .frame(width: 10, height: 10)
                            Text(cat?.displayName ?? id)
                        }
                    }
                }

                CleanProSection("On This Device") {
                    LabeledContent("Times spun", value: "\(spinCount)")
                }

                CleanProSection("Host Rating") {
                    Text(movie.hostRating.map { $0.formatted() } ?? "The hosts haven't scored this one in the app yet.")
                        .foregroundStyle(movie.hostRating == nil ? .secondary : .primary)
                }

                listenSection
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                CleanProBackground()
                backdrop
            }
        }
        .navigationTitle(movie.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Blurred artwork wash behind the header. Decoded at 40 pt (about 120 px),
    /// so the blur works on a tiny bitmap, not the full-size art.
    private var backdrop: some View {
        GeometryReader { proxy in
            ArtworkImage(urls: artworkURLs, pointSize: 40, cornerRadius: 0, showsPlaceholder: false)
                .frame(width: proxy.size.width, height: 420)
                .blur(radius: 40, opaque: true)
                .opacity(colorScheme == .dark ? 0.45 : 0.4)
                .mask {
                    LinearGradient(colors: [.black, .black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                }
                .clipped()
        }
        .frame(height: 420)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var listenSection: some View {
        CleanProSection("Listen") {
            if let title = movie.episodeTitle ?? movie.episodeIds.first.flatMap({
                EpisodeLabel.title(forEpisodeId: $0, movie: movie, episodesByGUID: episodesByGUID)
            }) {
                if let url = PodcastLinks.appleSearch(episodeTitle: title, show: show) {
                    Link(destination: url) {
                        Label("Find on Apple Podcasts", systemImage: "apple.logo")
                    }
                }
                if let url = PodcastLinks.spotifySearch(episodeTitle: title) {
                    Link(destination: url) {
                        Label("Find on Spotify", systemImage: "waveform")
                    }
                }
            }
            if let guid = movie.episodeIds.first,
               let url = PodcastLinks.buzzsproutEpisode(guid: guid, show: show) {
                Link(destination: url) {
                    Label("Open on Buzzsprout", systemImage: "globe")
                }
            }
        }
    }

    private var yourTake: some View {
        CleanProSection(
            "Your Take",
            footer: autoShareRatings
                ? "Your stars and watchlist are saved on this device. Auto-share is on, so your stars are also added anonymously to the listener average."
                : "Your stars and watchlist stay on this device."
        ) {
            HStack {
                Text("My rating")
                Spacer()
                StarRatingView(halfStars: myRating, tint: .orange) { half in
                    personal.setHalfStars(half, for: movie.id)
                    if autoShareRatings, let half {
                        Task { await community.submitListenerRating(movieId: movie.id, halfStars: half) }
                    }
                }
                .accessibilityIdentifier("my-rating-stars")
            }
            if let myRating {
                Text("\(HalfStars.label(myRating)) of 5 · drag across the stars or tap a star's left half for ½")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Picker("Status", selection: statusBinding) {
                Text("None").tag(WatchStatus?.none)
                Text("Want to Watch").tag(WatchStatus?.some(.wantToWatch))
                Text("Watched").tag(WatchStatus?.some(.watched))
            }
            .pickerStyle(.segmented)
        }
    }

    private var artworkURLs: [URL] {
        ArtworkResolver.candidates(for: movie, episodesByGUID: episodesByGUID, showArtwork: showArtworkURL)
    }

    /// Large artwork (from the movie's Buzzsprout episode) with the title under it.
    private var header: some View {
        VStack(spacing: 14) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: Self.artworkSide)
                .overlay {
                    ArtworkImage(urls: artworkURLs, pointSize: Self.artworkSide, cornerRadius: 22)
                }
                .shadow(color: .black.opacity(0.10), radius: 3, y: 2)
                .shadow(color: .black.opacity(0.22), radius: 20, y: 12)
                .padding(.horizontal, 24)
            VStack(spacing: 4) {
                Text(movie.title)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                Text(verbatim: catalog?.subtitle(for: movie) ?? "\(movie.year) · \(movie.genre)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if movie.isInfamous {
                    Label("Infamous", systemImage: "flame.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    static let artworkSide: CGFloat = 320

    private var episodesSection: some View {
        CleanProSection("Episodes") {
            if movie.episodeIds.isEmpty {
                Text("Not discussed on the show yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(movie.episodeIds.enumerated()), id: \.element) { index, guid in
                    if index > 0 { Divider() }
                    if linksEpisodes {
                        NavigationLink(value: MoviesRoute.episode(guid)) {
                            HStack {
                                episodeRow(guid)
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("movie-episode-\(guid)")
                    } else {
                        episodeRow(guid)
                    }
                }
            }
        }
    }

    private func episodeRow(_ guid: String) -> some View {
        let ep = episodesByGUID[guid]
        return HStack(spacing: 12) {
            if let ep {
                ArtworkImage(
                    urls: ArtworkResolver.candidates(for: ep, showArtwork: showArtworkURL),
                    pointSize: 44, cornerRadius: 8, placeholderSymbol: "mic"
                )
                .frame(width: 44, height: 44)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(EpisodeLabel.title(forEpisodeId: guid, movie: movie, episodesByGUID: episodesByGUID))
                    .font(.body.weight(.semibold))
                if let se = ep?.seasonEpisodeLabel {
                    Text(se).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(guid)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}
