import SwiftUI
import MRTCore
import MRTShared

/// Movies tab (mockup 07): search, scrolling filter chips, sort, 4-column grid.
struct TVMoviesView: View {
    let catalog: MovieCatalog?
    let loadState: RouletteViewModel.LoadState
    let history: SpinHistoryStore
    let episodesByGUID: [String: PodcastEpisode]
    let showArtworkURL: URL?
    var onOpen: (Movie) -> Void
    var onRetry: () -> Void

    enum Sort: String, CaseIterable, Identifiable {
        case az, za, newest, oldest, mostSpun
        var id: String { rawValue }
        var label: String {
            switch self {
            case .az: return "A–Z"
            case .za: return "Z–A"
            case .newest: return "Newest"
            case .oldest: return "Oldest"
            case .mostSpun: return "Most spun"
            }
        }
    }

    enum Filter: Hashable {
        case all, watchlist, rated, category(String)
    }

    @Environment(\.colorScheme) private var scheme
    @Environment(PersonalRatingsStore.self) private var personal
    @FocusState private var searchFocused: Bool
    @State private var query = ""
    @State private var sort: Sort = .az
    @State private var filter: Filter = .all

    private var theme: TVTheme { TVTheme(scheme: scheme) }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 24), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            TVScreenTitle(text: "Movies")
            if catalog == nil {
                unavailable
            } else {
                searchRow
                chips
                Text(summaryLine)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(theme.secondary)
                    .accessibilityIdentifier("tv.movies.summary")
                grid
            }
        }
        .padding(.horizontal, 80)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .accessibilityIdentifier("tv.screen.movies")
    }

    @ViewBuilder
    private var unavailable: some View {
        switch loadState {
        case .failed(let message):
            TVStatusView(
                title: "Couldn’t Load Movies",
                systemImage: "film",
                message: message,
                retryTitle: "Try again",
                retry: onRetry
            )
            .accessibilityIdentifier("tv.movies.error")
        default:
            TVStatusView(title: "Loading movies…", systemImage: "film")
                .accessibilityIdentifier("tv.movies.loading")
        }
    }

    private var searchRow: some View {
        HStack(spacing: 24) {
            HStack(spacing: 16) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 32, weight: .semibold))
                TextField("Search \(catalog?.movies.count ?? 0) movies", text: $query)
                    .font(.system(size: 34, weight: .medium))
                    .focused($searchFocused)
            }
            .foregroundStyle(searchFocused ? theme.ink : theme.text)
            .padding(.horizontal, 28)
            .frame(height: 84)
            .background(Capsule().fill(searchFocused ? Color.white : theme.field))
            .overlay(Capsule().strokeBorder(theme.teal.opacity(searchFocused ? 0.95 : 0), lineWidth: 4))
            .shadow(color: theme.teal.opacity(searchFocused ? 0.65 : 0), radius: searchFocused ? 20 : 0)
            .accessibilityIdentifier("tv.movies.search")

            Menu {
                ForEach(Sort.allCases) { option in
                    Button(option.label) { sort = option }
                }
            } label: {
                HStack(spacing: 12) {
                    Text("Sort")
                        .foregroundStyle(theme.secondary)
                    Text(sort.label)
                        .foregroundStyle(theme.text)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(theme.secondary)
                }
                .font(.system(size: 32, weight: .semibold))
                .padding(.horizontal, 28)
                .frame(height: 84)
                .background(Capsule().fill(theme.card))
            }
            .accessibilityIdentifier("tv.movies.sort")
        }
        .onAppear { TVFocus.soon { searchFocused = true } }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                chip("All", tag: .all, tint: theme.teal)
                    .accessibilityIdentifier("tv.movies.filter.all")
                chip("Watchlist", tag: .watchlist, tint: theme.teal)
                    .accessibilityIdentifier("tv.movies.filter.watchlist")
                chip("Rated by Me", tag: .rated, tint: theme.teal)
                    .accessibilityIdentifier("tv.movies.filter.rated")
                if let categories = catalog?.categories {
                    ForEach(categories) { category in
                        chip(category.name, tag: .category(category.id), tint: Color(hex: category.displayHex))
                            .accessibilityIdentifier("tv.movies.filter.\(category.id)")
                    }
                }
            }
            .padding(.trailing, 48)
        }
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.9),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading, endPoint: .trailing
            )
        }
    }

    private func chip(_ title: String, tag: Filter, tint: Color) -> some View {
        let on = filter == tag
        return Button { filter = tag } label: {
            HStack(spacing: 10) {
                if on { Circle().fill(Color.white).frame(width: 12, height: 12) }
                Text(title)
            }
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(on ? Color.white : theme.text)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(Capsule().fill(on ? tint : theme.cardAlt))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder
    private var grid: some View {
        if filtered.isEmpty {
            TVStatusView(
                title: emptyTitle,
                systemImage: emptySymbol,
                message: emptyMessage
            )
            .accessibilityIdentifier("tv.movies.empty")
        } else {
            VStack(spacing: 8) {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(filtered) { movie in
                            Button { onOpen(movie) } label: {
                                TVMovieCard(movie: movie, catalog: catalog)
                            }
                            .buttonStyle(TVPlainButtonStyle())
                            .accessibilityIdentifier("tv.movie.\(movie.id)")
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 36)
                }
                Text("SELECT  Search with keyboard or Siri dictation")
                    .font(.system(size: 24))
                    .foregroundStyle(theme.secondary)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("tv.movies.searchHint")
            }
        }
    }

    private var filtered: [Movie] {
        guard let catalog else { return [] }
        let stats = history.stats
        var list: [Movie]
        switch filter {
        case .all: list = catalog.movies
        case .watchlist: list = MovieListFilter.watchlist.apply(to: catalog.movies, ratings: personal.ratings, spinStats: stats)
        case .rated: list = MovieListFilter.rated.apply(to: catalog.movies, ratings: personal.ratings, spinStats: stats)
        case .category(let id): list = catalog.movies.filter { $0.categories.contains(id) }
        }
        if !query.isEmpty {
            let q = query.lowercased()
            list = list.filter {
                $0.title.lowercased().contains(q)
                    || $0.genre.lowercased().contains(q)
                    || ($0.episodeTitle?.lowercased().contains(q) ?? false)
                    || $0.categories.contains { catalog.category(withId: $0)?.name.lowercased().contains(q) == true }
            }
        }
        switch sort {
        case .az:
            list.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .za:
            list.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        case .newest:
            list.sort { $0.year == $1.year ? $0.title < $1.title : $0.year > $1.year }
        case .oldest:
            list.sort { $0.year == $1.year ? $0.title < $1.title : $0.year < $1.year }
        case .mostSpun:
            list.sort {
                let a = stats.spinCount(forMovie: $0.id)
                let b = stats.spinCount(forMovie: $1.id)
                if a == b { return $0.title < $1.title }
                return a > b
            }
        }
        return list
    }

    private var summaryLine: String {
        let count = filtered.count
        let noun = count == 1 ? "movie" : "movies"
        return "\(count) \(noun) · \(filterLabel) · \(sort.label)"
    }

    private var filterLabel: String {
        switch filter {
        case .all: return "All"
        case .watchlist: return "Watchlist"
        case .rated: return "Rated by Me"
        case .category(let id): return catalog?.category(withId: id)?.name ?? id
        }
    }

    private var emptyTitle: String {
        if !query.isEmpty { return "No Matches" }
        switch filter {
        case .watchlist: return "Watchlist Is Empty"
        case .rated: return "No Ratings Yet"
        case .all, .category: return "No Movies"
        }
    }

    private var emptySymbol: String {
        switch filter {
        case .watchlist: return "bookmark"
        case .rated: return "star"
        default: return query.isEmpty ? "film" : "magnifyingglass"
        }
    }

    private var emptyMessage: String {
        if !query.isEmpty { return "Nothing matches “\(query)”." }
        switch filter {
        case .watchlist: return "Open a movie and add it to your watchlist."
        case .rated: return "Open a movie and rate it with the remote."
        case .category: return "No films in this category."
        case .all: return "The movie list is empty."
        }
    }
}

struct TVMovieCard: View {
    let movie: Movie
    let catalog: MovieCatalog?
    @Environment(\.isFocused) private var isFocused
    @Environment(\.colorScheme) private var scheme

    private var theme: TVTheme { TVTheme(scheme: scheme) }
    private var bar: Color {
        Color(hex: catalog?.category(withId: movie.categories.first ?? "")?.displayHex ?? "#8E8E93")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(bar)
                .frame(height: 8)
                .padding(.top, 8)
            Text(movie.title)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(isFocused ? theme.ink : theme.text)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                Circle().fill(bar).frame(width: 12, height: 12)
                Text(cardMeta)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(isFocused ? theme.ink.opacity(0.7) : theme.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(isFocused ? Color.white : theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(isFocused ? Color.clear : theme.cardStroke, lineWidth: 2)
        )
        .shadow(color: theme.teal.opacity(isFocused ? 0.7 : 0), radius: isFocused ? 22 : 0)
        .scaleEffect(isFocused ? 1.08 : 1)
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }

    private var cardMeta: String {
        let name = movie.categories.first.flatMap { catalog?.category(withId: $0)?.name } ?? movie.genre
        return "\(movie.year) · \(name)"
    }
}
