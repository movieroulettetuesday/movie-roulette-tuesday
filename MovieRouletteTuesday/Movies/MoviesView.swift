import SwiftUI
import MRTCore
import MRTShared

struct MoviesView: View {
    let catalog: MovieCatalog?
    let history: SpinHistoryStore
    var episodesByGUID: [String: PodcastEpisode] = [:]
    /// Feed store, for show artwork and for loading an episode opened from a
    /// movie page before the feed has arrived.
    var episodeStore: EpisodeStore? = nil
    /// Set by a deep link (`mrt://movie/<id>`); consumed once the catalog is loaded.
    var pendingMovieID: Binding<String?> = .constant(nil)

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Selected movie in the split view (regular width).
    @State private var selectedMovieID: String?
    /// Navigation path in the stack (compact width): `[.movie(id), .episode(guid)…]`.
    /// Converted to/from the split-view state when the size class changes, so
    /// selection and a pushed episode survive iPad Split View resizing.
    @State private var path: [MoviesRoute] = []
    /// Episodes pushed in the split view's detail column, tagged with the movie
    /// they belong to: selecting another movie starts a fresh detail stack.
    @State private var detailStack = DetailStack()

    private struct DetailStack: Equatable {
        var movieID: String?
        var routes: [MoviesRoute] = []
    }

    private var showArtworkURL: URL? { episodeStore?.showArtworkURL }
    @State private var query = ""
    @State private var showsSuggest = false
    @State private var categoryFilter: String? = nil  // category id
    @State private var sort: MovieSort = .title
    @State private var listFilter: MovieListFilter = .all
    @State private var onMyServices = false
    @AppStorage(MyServices.storageKey) private var myServicesRaw = ""
    private var myServices: MyServices { MyServices(serialized: myServicesRaw) }
    private var hasStreamingData: Bool { catalog?.movies.contains { $0.streaming != nil } ?? false }
    @Environment(PersonalRatingsStore.self) private var personal

    enum MovieSort: String, CaseIterable, Identifiable {
        case title, yearNewest, yearOldest, spins, availableFirst
        var id: String { rawValue }
        var label: String {
            switch self {
            case .title: return "Title"
            case .yearNewest: return "Newest first"
            case .yearOldest: return "Oldest first"
            case .spins: return "Most spun"
            case .availableFirst: return "Available first"
            }
        }
    }

    private var stats: SpinStats { history.stats }

    private var filtered: [Movie] {
        guard let catalog else { return [] }
        let stats = self.stats  // one read for the whole filter + sort
        var list = listFilter.apply(to: catalog.movies, ratings: personal.ratings, spinStats: stats)
        if let categoryFilter {
            list = list.filter { $0.categories.contains(categoryFilter) }
        }
        let services = myServices
        if onMyServices {
            list = StreamingCatalog.filter(list, services: services)
        }
        if !query.isEmpty {
            let q = query.lowercased()
            list = list.filter {
                $0.title.lowercased().contains(q)
                || $0.genre.lowercased().contains(q)
                || ($0.episodeTitle?.lowercased().contains(q) ?? false)
            }
        }
        switch sort {
        case .title: list.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .yearNewest: list.sort { $0.year == $1.year ? $0.title < $1.title : $0.year > $1.year }
        case .yearOldest: list.sort { $0.year == $1.year ? $0.title < $1.title : $0.year < $1.year }
        case .spins:
            list.sort {
                let a = stats.spinCount(forMovie: $0.id)
                let b = stats.spinCount(forMovie: $1.id)
                if a == b { return $0.title < $1.title }
                return a > b
            }
        case .availableFirst:
            list.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            list = StreamingCatalog.availableFirst(list, services: services)
        }
        return list
    }

    private var isRegular: Bool { horizontalSizeClass == .regular }

    var body: some View {
        Group {
            if isRegular {
                NavigationSplitView {
                    sidebarContent
                        .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 460)
                } detail: {
                    NavigationStack(path: detailPath) {
                        Group {
                            if let id = selectedMovieID, let movie = catalog?.movie(withId: id) {
                                detail(for: movie)
                            } else {
                                ContentUnavailableView(
                                    "Pick a Movie",
                                    systemImage: "film.stack",
                                    description: Text("Choose a film from the list to see its page, episodes and ratings.")
                                )
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background { CleanProBackground() }
                            }
                        }
                        .navigationDestination(for: MoviesRoute.self) { destination(for: $0) }
                    }
                    // New identity per movie so the detail's scroll/state resets.
                    .id(selectedMovieID)
                }
            } else {
                NavigationStack(path: $path) {
                    sidebarContent
                        .navigationDestination(for: MoviesRoute.self) { destination(for: $0) }
                }
            }
        }
        .onChange(of: isRegular) { _, regular in
            if regular {
                let state = MoviesNavigation.regular(fromCompactPath: path)
                if let id = state.selectedMovieID {
                    selectedMovieID = id
                    detailStack = DetailStack(movieID: id, routes: state.detailPath)
                }
            } else {
                path = MoviesNavigation.compactPath(from: .init(
                    selectedMovieID: selectedMovieID,
                    detailPath: detailStack.movieID == selectedMovieID ? detailStack.routes : []
                ))
            }
        }
        .onChange(of: pendingMovieID.wrappedValue) { _, _ in consumePendingLink() }
        .onChange(of: catalog?.movies.count) { _, _ in consumePendingLink() }
        .onAppear { consumePendingLink() }
    }

    private var sidebarContent: some View {
        Group {
            if catalog == nil {
                ProgressView("Loading catalog…")
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .cleanProListScreen()
        .navigationTitle("Movies")
        .searchable(text: $query, prompt: "Title, genre, episode")
        .toolbar { toolbar }
        .sheet(isPresented: $showsSuggest) {
            SuggestMovieSheet(categories: catalog?.categories ?? [])
                .presentationDetents([.fraction(0.62), .large])
        }
    }

    /// The detail column's path, scoped to the selected movie.
    private var detailPath: Binding<[MoviesRoute]> {
        Binding(
            get: { detailStack.movieID == selectedMovieID ? detailStack.routes : [] },
            set: { detailStack = DetailStack(movieID: selectedMovieID, routes: $0) }
        )
    }

    private func detail(for movie: Movie) -> some View {
        MoviePageView(
            movie: movie,
            catalog: catalog,
            episodesByGUID: episodesByGUID,
            showArtworkURL: showArtworkURL,
            context: .moviesTab
        )
    }

    @ViewBuilder
    private func destination(for route: MoviesRoute) -> some View {
        switch route {
        case .movie(let id):
            if let movie = catalog?.movie(withId: id) {
                detail(for: movie)
            } else {
                ContentUnavailableView("Movie Not Found", systemImage: "film")
            }
        case .episode(let guid):
            LinkedEpisodeView(guid: guid, store: episodeStore, catalog: catalog)
        }
    }

    /// Opens the deep-linked movie in whichever layout is showing. Waits for
    /// the catalog; unknown ids are dropped quietly.
    private func consumePendingLink() {
        guard let id = pendingMovieID.wrappedValue, let catalog else { return }
        pendingMovieID.wrappedValue = nil
        guard catalog.movie(withId: id) != nil else { return }
        selectedMovieID = id
        detailStack = DetailStack(movieID: id)
        path = [.movie(id)]
        #if DEBUG
        FileHandle.standardError.write(Data("MRT-LINK opened \(id) regular=\(isRegular)\n".utf8))
        #endif
    }

    @ViewBuilder
    private var list: some View {
        ScrollViewReader { proxy in
            Group {
                if isRegular {
                    List(selection: $selectedMovieID) { streamingChips; suggestSection; listSection }
                } else {
                    List { streamingChips; suggestSection; listSection }
                }
            }
            .overlay { emptyOverlay }
            #if DEBUG
            .task { await DebugScroll.runIfRequested(proxy: proxy, ids: { filtered.map(\.id) }) }
            #endif
        }
    }

    /// "On my services" / "Available first" chips (approved mockup 6b).
    @ViewBuilder
    private var streamingChips: some View {
        if hasStreamingData {
            Section {
                let chips = Group {
                    chip("On my services", on: onMyServices) {
                        onMyServices.toggle()
                    }
                    .accessibilityIdentifier("chip-my-services")
                    chip("Available first", on: sort == .availableFirst) {
                        sort = sort == .availableFirst ? .title : .availableFirst
                    }
                    .accessibilityIdentifier("chip-available-first")
                }
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        // Stacked: both chips fully visible, no sideways scrolling.
                        VStack(alignment: .leading, spacing: 8) { chips }
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) { chips }
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                if onMyServices && myServices.isEmpty {
                    Text("Choose your services in Settings › My Services.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(on ? Color.white : Color.primary)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(on ? AnyShapeStyle(Brand.tealDark) : AnyShapeStyle(.thinMaterial), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// "Suggest a movie" entry (approved v4 mockup). Hidden while searching or
    /// filtering so results stay on top.
    @ViewBuilder
    private var suggestSection: some View {
        if query.isEmpty && categoryFilter == nil && listFilter == .all && !onMyServices {
            Section {
                SuggestMovieRow { showsSuggest = true }
            }
        }
    }

    private var listSection: some View {
        let rows = filtered
        let stats = self.stats
        return Section {
            ForEach(rows) { movie in
                let row = MovieRow(
                    movie: movie,
                    catalog: catalog,
                    spinCount: stats.spinCount(forMovie: movie.id),
                    entry: personal.entry(for: movie.id),
                    service: StreamingCatalog.matchingServices(movie, services: myServices).first,
                    artworkURLs: ArtworkResolver.candidates(
                        for: movie, episodesByGUID: episodesByGUID, showArtwork: showArtworkURL
                    )
                )
                // Value-based: selects in the split view (String selection),
                // pushes a route in the stack.
                if isRegular {
                    NavigationLink(value: movie.id) { row }
                } else {
                    NavigationLink(value: MoviesRoute.movie(movie.id)) { row }
                }
            }
        } footer: {
                let total = catalog?.movies.count ?? 0
                Text(listFilter == .all
                     ? "\(rows.count) of \(total) movies"
                     : "\(rows.count) of \(total) movies · \(listFilter.label)")
        }
    }

    @ViewBuilder
    private var emptyOverlay: some View {
            if catalog != nil, filtered.isEmpty, !query.isEmpty {
                ContentUnavailableView.search(text: query)
            } else if catalog != nil, filtered.isEmpty, listFilter == .all {
                ContentUnavailableView(
                    "No Matches",
                    systemImage: "film",
                    description: Text("Try a different category or service filter.")
                )
            } else if catalog != nil, filtered.isEmpty, listFilter != .all {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: emptySymbol)
                } description: {
                    Text(emptyMessage)
                }
            }
    }

    private var emptyTitle: String {
        switch listFilter {
        case .watchlist: return "Watchlist Is Empty"
        case .watched: return "Nothing Marked Watched"
        case .rated: return "No Ratings Yet"
        case .notSpunYet: return "You’ve Spun Them All"
        case .all: return "No Movies"
        }
    }

    private var emptySymbol: String {
        switch listFilter {
        case .watchlist: return "bookmark"
        case .watched: return "checkmark.circle"
        case .rated: return "star"
        case .notSpunYet: return "trophy"
        case .all: return "film"
        }
    }

    private var emptyMessage: String {
        switch listFilter {
        case .watchlist: return "Open a movie and set its status to Want to watch."
        case .watched, .rated: return "Open a movie to rate it or mark it watched."
        case .notSpunYet: return "Every movie in this view has come up on the wheel."
        case .all: return ""
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Button("All categories") { categoryFilter = nil }
                Divider()
                if let cats = catalog?.categories {
                    ForEach(cats) { cat in
                        Button {
                            categoryFilter = cat.id
                        } label: {
                            if categoryFilter == cat.id {
                                Label(cat.displayName, systemImage: "checkmark")
                            } else {
                                Text(cat.displayName)
                            }
                        }
                    }
                }
            } label: {
                Label(
                    categoryFilter.flatMap { catalog?.category(withId: $0)?.name } ?? "Category",
                    systemImage: "line.3.horizontal.decrease.circle"
                )
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Show", selection: $listFilter) {
                    ForEach(MovieListFilter.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            } label: {
                Label(
                    listFilter == .all ? "Show" : listFilter.label,
                    systemImage: listFilter == .all ? "bookmark" : "bookmark.fill"
                )
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                ForEach(MovieSort.allCases) { option in
                    Button {
                        sort = option
                    } label: {
                        if sort == option {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
        }
    }
}

private struct MovieRow: View {
    let movie: Movie
    let catalog: MovieCatalog?
    let spinCount: Int
    var entry: PersonalMovieEntry? = nil
    /// First of my services this movie streams on (logo on the row).
    var service: StreamingInfo.Provider? = nil
    var artworkURLs: [URL] = []

    var body: some View {
        HStack(spacing: 12) {
            ArtworkImage(urls: artworkURLs, pointSize: 52, cornerRadius: 10)
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(movie.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    categoryDots
                    Text(verbatim: catalog?.subtitle(for: movie) ?? "\(movie.year) · \(movie.genre)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let service {
                ProviderLogo(provider: service, size: 30)
                    .accessibilityLabel("On \(service.name)")
            }
            personalIndicators
            if spinCount > 0 {
                Text("×\(spinCount)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var personalIndicators: some View {
        if let half = entry?.halfStars {
            let stars = HalfStars.label(half)
            Label(stars, systemImage: "star.fill")
                .labelStyle(.titleAndIcon)
                .font(.caption.weight(.bold))
                .foregroundStyle(.orange)
                .accessibilityLabel("Your rating \(stars) of 5")
        }
        switch entry?.status {
        case .wantToWatch?:
            Image(systemName: "bookmark.fill")
                .font(.caption)
                .foregroundStyle(Brand.accentPeach)
                .accessibilityLabel("On your watchlist")
        case .watched?:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Brand.accentTeal)
                .accessibilityLabel("Watched")
        case nil:
            EmptyView()
        }
    }

    private var categoryDots: some View {
        HStack(spacing: 3) {
            ForEach(movie.categories.prefix(3), id: \.self) { id in
                Circle()
                    .fill(CleanPro.category(catalog?.category(withId: id)))
                    .frame(width: 8, height: 8)
            }
        }
    }
}

/// An episode opened from a movie page. If the feed hasn't loaded it yet,
/// loads the feed (sharing any in-flight request) and then shows it; if it's
/// still missing, says so with a retry.
struct LinkedEpisodeView: View {
    let guid: String
    let store: EpisodeStore?
    let catalog: MovieCatalog?

    @State private var attemptedLoad = false

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { CleanProBackground() }
    }

    @ViewBuilder
    private var content: some View {
        if let episode = store?.episode(guid: guid) {
            EpisodeDetailView(
                episode: episode,
                catalog: catalog,
                show: catalog?.showInfo ?? .mrt,
                showArtworkURL: store?.showArtworkURL,
                showsFilmLink: false
            )
        } else if let store, !attemptedLoad || store.loadState == .loading {
            ProgressView("Loading episode…")
                .task {
                    await store.load()
                    attemptedLoad = true
                }
        } else {
            ContentUnavailableView {
                Label("Episode Not Available", systemImage: "mic.slash")
            } description: {
                Text("This episode isn’t available right now. Check your connection and try again.")
            } actions: {
                if let store {
                    Button("Try again") {
                        Task { await store.load(forceNetwork: true) }
                    }
                }
            }
        }
    }
}

#Preview {
    MoviesView(catalog: nil, history: SpinHistoryStore(fileStore: nil))
        .environment(PersonalRatingsStore(fileStore: nil))
        .environment(SpinHistoryStore(fileStore: nil))
        .environment(CommunityService.preview())
}
