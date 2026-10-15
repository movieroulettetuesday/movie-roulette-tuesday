import SwiftUI

struct StatsView: View {
    let history: SpinHistoryStore
    let catalog: MovieCatalog?
    @Environment(PersonalRatingsStore.self) private var personal
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Regular width: a multi-column card grid. Compact: a single column of cards.
    private var usesGrid: Bool { horizontalSizeClass == .regular }

    private var mine: PersonalRatingsSummary {
        PersonalRatingsSummary(ratings: personal.ratings, catalog: catalog)
    }

    private var snap: StatsCalculator.Snapshot {
        StatsCalculator.snapshot(history: history.results, catalog: catalog, archive: history.archive)
    }

    var body: some View {
        NavigationStack {
            Group {
                let summary = mine
                if snap.totalSpins == 0 && summary.ratedCount == 0 && summary.watchlistCount == 0 && summary.watchedCount == 0 {
                    ContentUnavailableView {
                        Label("No Stats Yet", systemImage: "chart.bar")
                    } description: {
                        Text("Spin the wheel or rate a movie to see your stats.")
                    }
                } else {
                    // One column of cards on iPhone / narrow windows; a
                    // multi-column card grid in regular width.
                    GeometryReader { proxy in
                        let count = StatsGridLayout.columnCount(forWidth: proxy.size.width, isRegularWidth: usesGrid)
                        ScrollView {
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), spacing: CleanPro.spacing, alignment: .top), count: count),
                                alignment: .leading,
                                spacing: CleanPro.spacing
                            ) {
                                sections(summary)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { CleanProBackground() }
            .navigationTitle("Stats")
        }
    }

    @ViewBuilder
    private func sections(_ summary: PersonalRatingsSummary) -> some View {
        if snap.totalSpins > 0 {
            overview
            favorites
        }
        if summary.ratedCount > 0 || summary.watchlistCount > 0 || summary.watchedCount > 0 {
            yourRatings(summary)
        }
        if !snap.categoryBreakdown.isEmpty { categories }
        if !snap.genreBreakdown.isEmpty { genres }
        if snap.totalSpins > 0 { recent }
    }

    /// One Clean Pro card per group (title, rows, optional footer).
    private func group<Content: View>(
        _ title: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        CleanProSection(title, footer: footer, content: content)
    }

    private var overview: some View {
        group("This Device") {
            LabeledContent("Total spins", value: "\(snap.totalSpins)")
            LabeledContent("Different movies", value: "\(snap.distinctMovies)")
            if let catalog {
                LabeledContent("Catalog size", value: "\(catalog.movies.count) films")
            }
        }
    }

    private var favorites: some View {
        group("Most Spun") {
            if let top = snap.mostSpunMovie {
                LabeledContent {
                    Text("×\(top.count)")
                } label: {
                    Text(catalog?.movie(withId: top.id)?.title ?? top.id)
                }
            }
            if let top = snap.mostSpunCategory {
                LabeledContent {
                    Text("×\(top.count)")
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(CleanPro.category(catalog?.category(withId: top.id)))
                            .frame(width: 10, height: 10)
                        Text(catalog?.category(withId: top.id)?.displayName ?? top.id)
                    }
                }
            }
        }
    }

    private func yourRatings(_ mine: PersonalRatingsSummary) -> some View {
        group(
            "Your Ratings",
            footer: mine.topRated.isEmpty ? nil : "Your top-rated movies."
        ) {
            LabeledContent("Movies rated", value: "\(mine.ratedCount)")
            if let average = mine.averageStars {
                LabeledContent("Your average") {
                    Text("\(HalfStars.label(stars: average)) ★")
                }
            }
            LabeledContent("Watched", value: "\(mine.watchedCount)")
            LabeledContent("On your watchlist", value: "\(mine.watchlistCount)")
            ForEach(mine.topRated, id: \.movieId) { rated in
                HStack {
                    Text(rated.title)
                        .lineLimit(1)
                    Spacer()
                    StarRatingView(halfStars: rated.halfStars, font: .caption, tint: .orange)
                }
            }
            if FeatureFlags.showHostRatings, let diff = mine.averageDifferenceFromHosts {
                LabeledContent("You vs hosts") {
                    if abs(diff) < 0.05 {
                        Text("Right in line")
                    } else {
                        Text("\(diff, format: .number.precision(.fractionLength(1)).sign(strategy: .always())) ★")
                    }
                }
                ForEach(mine.versusHosts, id: \.movieId) { row in
                    LabeledContent(row.title) {
                        Text("You \(HalfStars.label(row.yourHalfStars)) · Hosts \(row.hostRating, format: .number.precision(.fractionLength(0...1)))")
                    }
                }
            }
        }
    }

    private var categories: some View {
        group("By Category") {
            ForEach(snap.categoryBreakdown, id: \.id) { row in
                let cat = catalog?.category(withId: row.id)
                HStack {
                    Circle()
                        .fill(CleanPro.category(cat))
                        .frame(width: 10, height: 10)
                    Text(cat?.displayName ?? row.id)
                    Spacer()
                    Text("×\(row.count)")
                        .foregroundStyle(.secondary)
                    // Simple relative bar
                    Capsule()
                        .fill(CleanPro.category(cat).opacity(0.55))
                        .frame(width: barWidth(count: row.count, max: snap.categoryBreakdown.first?.count ?? 1), height: 8)
                }
            }
        }
    }

    private var genres: some View {
        group("By Genre") {
            ForEach(snap.genreBreakdown.prefix(12), id: \.genre) { row in
                LabeledContent(row.genre, value: "×\(row.count)")
            }
        }
    }

    private var recent: some View {
        group("Recent Spins") {
            ForEach(snap.recent) { spin in
                HStack {
                    Circle()
                        .fill(CleanPro.category(catalog?.category(withId: spin.categoryId)))
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(catalog?.movie(withId: spin.movieId)?.title ?? spin.movieId)
                            .font(.body.weight(.semibold))
                        Text(catalog?.category(withId: spin.categoryId)?.displayName ?? spin.categoryId)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(spin.timestamp, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func barWidth(count: Int, max: Int) -> CGFloat {
        guard max > 0 else { return 0 }
        return CGFloat(count) / CGFloat(max) * 64
    }
}

#Preview {
    StatsView(history: SpinHistoryStore(fileStore: nil), catalog: nil)
        .environment(PersonalRatingsStore(fileStore: nil))
}
