import SwiftUI
import MRTCore
import MRTShared

/// Stats for this Apple TV (mockup 09). Only the last 100 spins are kept.
/// Settings is a button here, not a fifth tab.
struct TVStatsView: View {
    let history: SpinHistoryStore
    let catalog: MovieCatalog?
    var onOpenMovie: (Movie) -> Void
    var onSettings: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(PersonalRatingsStore.self) private var personal

    private var theme: TVTheme { TVTheme(scheme: scheme) }
    private var snap: StatsCalculator.Snapshot {
        StatsCalculator.snapshot(history: history.results, catalog: catalog, archive: history.archive, recentLimit: 8)
    }
    private var mine: PersonalRatingsSummary {
        PersonalRatingsSummary(ratings: personal.ratings, catalog: catalog)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    TVScreenTitle(text: "Stats")
                    Text("This Apple TV · last \(SpinHistoryStore.tvDetailLimit) spins")
                        .font(.system(size: 30))
                        .foregroundStyle(theme.secondary)
                }
                Spacer()
                Button(action: onSettings) {
                    Label("Settings", systemImage: "gearshape.fill")
                        .font(.system(size: 32, weight: .semibold))
                }
                .buttonStyle(TVPillButtonStyle(primary: false, width: 320, height: 84, fontSize: 32))
                .accessibilityIdentifier("tv.stats.settings")
            }
            if snap.totalSpins == 0 && mine.ratedCount == 0 && mine.watchlistCount == 0 {
                TVStatusView(
                    title: "No Stats Yet",
                    systemImage: "chart.bar",
                    message: "Spin the wheel or rate a movie. Only the last \(SpinHistoryStore.tvDetailLimit) spins are kept on this Apple TV."
                )
                .accessibilityIdentifier("tv.stats.empty")
            } else {
                HStack(alignment: .top, spacing: 48) {
                    left
                    recent
                        .frame(width: 640)
                }
                .padding(.top, 18)
            }
            Spacer(minLength: 0)
            Text("Only the last \(SpinHistoryStore.tvDetailLimit) spins are kept on Apple TV.")
                .font(.system(size: 24))
                .foregroundStyle(theme.secondary)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 80)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .accessibilityIdentifier("tv.screen.stats")
    }

    private var left: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 18) {
                statCard(value: "\(snap.totalSpins)", caption: snap.totalSpins == 1 ? "spin" : "spins")
                    .accessibilityIdentifier("tv.stats.spins")
                statCard(
                    value: snap.mostSpunCategory.flatMap { catalog?.category(withId: $0.id)?.name } ?? "—",
                    caption: snap.mostSpunCategory.map { "top category  ×\($0.count)" } ?? "top category"
                )
                statCard(
                    value: mine.averageStars.map { String(format: "%.1f", $0) } ?? "—",
                    caption: "your average",
                    star: mine.averageStars != nil
                )
                .accessibilityIdentifier("tv.stats.average")
            }
            if !snap.categoryBreakdown.isEmpty {
                Text("Spins by category")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(theme.text)
                VStack(spacing: 10) {
                    let maxCount = snap.categoryBreakdown.first?.count ?? 1
                    ForEach(snap.categoryBreakdown, id: \.id) { row in
                        categoryRow(row, maxCount: maxCount)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statCard(value: String, caption: String, star: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value)
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if star {
                    Image(systemName: "star.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Brand.jackpotGold)
                }
            }
            Text(caption)
                .font(.system(size: 24))
                .foregroundStyle(theme.secondary)
                .lineLimit(1)
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(theme.card))
    }

    private func categoryRow(_ row: CountedID, maxCount: Int) -> some View {
        let category = catalog?.category(withId: row.id)
        let width = max(24, CGFloat(row.count) / CGFloat(max(maxCount, 1)) * 520)
        return HStack(spacing: 16) {
            Text(category?.name ?? row.id)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(theme.text)
                .frame(width: 200, alignment: .leading)
                .lineLimit(1)
            Capsule()
                .fill(Color(hex: category?.displayHex ?? "#8E8E93"))
                .frame(width: width, height: 18)
            Spacer(minLength: 8)
            Text("\(row.count)")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(theme.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recent spins")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(theme.text)
            if snap.recent.isEmpty {
                Text("No spins yet")
                    .font(.system(size: 28))
                    .foregroundStyle(theme.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(snap.recent) { spin in
                            if let movie = catalog?.movie(withId: spin.movieId) {
                                Button { onOpenMovie(movie) } label: { recentRow(spin, movie: movie) }
                                    .buttonStyle(TVRowButtonStyle())
                                    .accessibilityIdentifier("tv.stats.spin.\(movie.id)")
                            }
                        }
                    }
                }
            }
        }
    }

    private func recentRow(_ spin: SpinResult, movie: Movie) -> some View {
        let category = catalog?.category(withId: spin.categoryId)
        return HStack(spacing: 16) {
            Circle()
                .fill(Color(hex: category?.displayHex ?? "#8E8E93"))
                .frame(width: 16, height: 16)
            Text(movie.title)
                .font(.system(size: 30, weight: .bold))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(category?.name ?? spin.categoryId) · \(TVFormat.spinWhen(spin.timestamp))")
                .font(.system(size: 24))
                .lineLimit(1)
        }
    }
}
