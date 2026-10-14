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

                if let streaming = movie.streaming, !streaming.isEmpty {
                    WhereToWatchSection(streaming: streaming)
                }

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

                if FeatureFlags.showHostRatings {
                    CleanProSection("Host Rating") {
                        Text(movie.hostRating.map { $0.formatted() } ?? "The hosts haven't scored this one in the app yet.")
                            .foregroundStyle(movie.hostRating == nil ? .secondary : .primary)
                    }
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


/// "Where to watch" (approved mockup 6a): Stream / Free / Rent or buy rows of
/// provider logos + names, the JustWatch/TMDB attribution with the update
/// date, and "All options on TMDB". Shown only when there is data.
struct WhereToWatchSection: View {
    let streaming: StreamingInfo
    @AppStorage(MyServices.storageKey) private var myServicesRaw = ""

    private var services: MyServices { MyServices(serialized: myServicesRaw) }

    private var footer: String {
        if let date = StreamingCatalog.updatedLabel(streaming.updated) {
            return "\(StreamingCatalog.attribution) · updated \(date)"
        }
        return StreamingCatalog.attribution
    }

    var body: some View {
        CleanProSection("Where to Watch · \(streaming.region)", footer: footer) {
            row("Stream", streaming.stream, id: "stream")
            row("Free", streaming.free, id: "free")
            row("Rent or buy", StreamingCatalog.rentOrBuy(streaming), id: "rent-buy")
            if let link = streaming.link.flatMap(URL.init(string:)) {
                Link(destination: link) {
                    HStack {
                        Text("All options on TMDB")
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.footnote)
                    }
                }
                .accessibilityIdentifier("streaming-tmdb-link")
            }
        }
        .accessibilityIdentifier("where-to-watch")
    }

    @ViewBuilder
    private func row(_ title: String, _ providers: [StreamingInfo.Provider], id: String) -> some View {
        if !providers.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title).font(.body.weight(.semibold))
                    Spacer()
                    if providers.contains(where: { services.contains($0.id) }) {
                        Text("Your service")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Brand.teal, in: Capsule())
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(providers, id: \.id) { p in
                            VStack(spacing: 4) {
                                ProviderLogo(provider: p, size: 44)
                                Text(p.name)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 64)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            .accessibilityIdentifier("streaming-\(id)")
        }
    }
}

/// A provider's TMDB logo (AsyncImage); its name on a tile while loading or when it fails.
struct ProviderLogo: View {
    let provider: StreamingInfo.Provider
    var size: CGFloat = 32

    var body: some View {
        AsyncImage(url: provider.logoURL) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    Brand.teal.opacity(0.85)
                    Text(provider.name)
                        .font(.system(size: max(8, size * 0.2), weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.5)
                        .padding(2)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityLabel(provider.name)
    }
}
