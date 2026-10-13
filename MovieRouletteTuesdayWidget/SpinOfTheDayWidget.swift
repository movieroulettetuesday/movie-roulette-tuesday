import SwiftUI
import WidgetKit

// MARK: - Timeline

struct SpinOfTheDayEntry: TimelineEntry {
    let date: Date
    /// Always available: computed from the cached GitHub catalog, else the bundled one.
    let pick: SpinOfTheDay.Pick?
    /// From the App Group (nil if the app hasn't written it yet, or the App Group is unavailable).
    let latestEpisode: WidgetSnapshot.EpisodeInfo?
    let lastSpin: WidgetSnapshot.SpinInfo?
}

struct SpinOfTheDayProvider: TimelineProvider {
    func placeholder(in context: Context) -> SpinOfTheDayEntry {
        SpinOfTheDayEntry.sample
    }

    func getSnapshot(in context: Context, completion: @escaping (SpinOfTheDayEntry) -> Void) {
        completion(context.isPreview ? .sample : makeEntry(for: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SpinOfTheDayEntry>) -> Void) {
        let now = Date()
        let entry = makeEntry(for: now)
        // Midnight brings a new Spin of the Day. The app also asks for a reload when it
        // publishes a new episode or spin.
        completion(Timeline(entries: [entry], policy: .after(SpinOfTheDay.nextRefresh(after: now))))
    }

    private func makeEntry(for date: Date) -> SpinOfTheDayEntry {
        let snapshot = WidgetSnapshotStore.appGroup()?.load()
        let pick = Self.loadCatalog().flatMap { SpinOfTheDay.pick(for: date, in: $0) }
        return SpinOfTheDayEntry(
            date: date,
            pick: pick,
            latestEpisode: snapshot?.latestEpisode,
            lastSpin: snapshot?.lastSpin
        )
    }

    /// The app's last good GitHub copy (App Group cache, same build), else the
    /// widget's own bundled movies.json. Read per timeline so updates show up.
    private static func loadCatalog() -> MovieCatalog? {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return LocalCatalog.loadSync(cache: CatalogCache.standard(build: build))
    }
}

extension SpinOfTheDayEntry {
    static let sample = SpinOfTheDayEntry(
        date: Date(),
        pick: SpinOfTheDay.Pick(
            movie: Movie(id: "the-outsiders-1983", title: "The Outsiders", year: 1983, genre: "Drama", categories: []),
            category: RouletteCategory(id: "cat-prestige", name: "Prestige", colorHex: "#6D597A"),
            dayKey: "sample"
        ),
        latestEpisode: WidgetSnapshot.EpisodeInfo(guid: "Buzzsprout-19913482", title: "The Outsiders", season: 4, episode: 34),
        lastSpin: nil
    )
}

// MARK: - Widget

struct SpinOfTheDayWidget: Widget {
    let kind = "SpinOfTheDayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SpinOfTheDayProvider()) { entry in
            SpinOfTheDayWidgetView(entry: entry)
        }
        .configurationDisplayName("Spin of the Day")
        .description("Today's pick from the Movie Roulette Tuesday wheel, plus the latest episode.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

// MARK: - Views

/// Widget colors: the Clean Pro background gradient and heading colors
/// (no materials). The widget follows the system appearance, not the app's
/// Appearance setting; text uses primary/secondary ink on the light or dark
/// gradient, headings use the contrast-checked Clean Pro heading color.
private struct WidgetPalette {
    let background: [Color]
    /// Small heading text ("SPIN OF THE DAY").
    let accent: Color

    init(_ scheme: ColorScheme) {
        if scheme == .dark {
            background = CleanProColors.backgroundDark.map { Color(hex: $0) }
            accent = Color(hex: CleanProColors.headingDark)
        } else {
            background = CleanProColors.backgroundLight.map { Color(hex: $0) }
            accent = Color(hex: CleanProColors.headingLight)
        }
    }
}

struct SpinOfTheDayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: SpinOfTheDayEntry

    private var palette: WidgetPalette { WidgetPalette(colorScheme) }

    var body: some View {
        content
            // Tapping opens today's pick in the Movies tab (mrt://movie/<id>).
            .widgetURL(entry.pick.map { DeepLink.movie(id: $0.movie.id).url })
            .containerBackground(for: .widget) {
                if family == .accessoryRectangular {
                    Color.clear
                } else {
                    LinearGradient(
                        colors: palette.background,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryRectangular:
            AccessoryView(entry: entry)
        case .systemLarge:
            VStack(alignment: .leading, spacing: 12) {
                PickView(pick: entry.pick, compact: false)
                if let pick = entry.pick {
                    Text(pick.movie.genre)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Divider()
                SecondaryView(entry: entry)
                if entry.latestEpisode != nil, let spin = entry.lastSpin {
                    Divider()
                    LastSpinView(spin: spin)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .systemMedium:
            HStack(alignment: .top, spacing: 12) {
                PickView(pick: entry.pick, compact: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                SecondaryView(entry: entry)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                PickView(pick: entry.pick, compact: true)
                Spacer(minLength: 0)
                if let episode = entry.latestEpisode {
                    Text("New: \(episode.seasonEpisodeLabel ?? episode.title)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(palette.accent)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct PickView: View {
    @Environment(\.colorScheme) private var colorScheme
    private var palette: WidgetPalette { WidgetPalette(colorScheme) }
    let pick: SpinOfTheDay.Pick?
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SPIN OF THE DAY")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(palette.accent)
            if let pick {
                if let category = pick.category {
                    Text(category.displayName)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.labelColor(onHex: category.displayHex))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(hex: category.displayHex), in: Capsule())
                        .lineLimit(1)
                }
                Text(pick.movie.title)
                    .font(compact ? Font.headline : Font.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(compact ? 3 : 2)
                    .minimumScaleFactor(0.8)
                Text(String(pick.movie.year))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Open the app to spin the wheel.")
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
        }
    }
}

private struct SecondaryView: View {
    @Environment(\.colorScheme) private var colorScheme
    private var palette: WidgetPalette { WidgetPalette(colorScheme) }
    let entry: SpinOfTheDayEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let episode = entry.latestEpisode {
                Text("LATEST EPISODE")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(palette.accent)
                if let label = episode.seasonEpisodeLabel {
                    Text(label)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                Text(episode.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                if let date = episode.pubDate {
                    Text(date, format: .dateTime.month(.abbreviated).day())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if let spin = entry.lastSpin {
                Text("YOUR LAST SPIN")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(palette.accent)
                Text(spin.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                Text(spin.categoryName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("MOVIE ROULETTE TUESDAY")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(palette.accent)
                Text("Open the app to load the latest episode.")
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
        }
    }
}

private struct LastSpinView: View {
    @Environment(\.colorScheme) private var colorScheme
    private var palette: WidgetPalette { WidgetPalette(colorScheme) }
    let spin: WidgetSnapshot.SpinInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("YOUR LAST SPIN")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(palette.accent)
            Text(spin.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text(spin.categoryName)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AccessoryView: View {
    let entry: SpinOfTheDayEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Spin of the Day")
                .font(.caption2.weight(.bold))
                .widgetAccentable()
            Text(entry.pick?.movie.title ?? "Movie Roulette")
                .font(.headline)
                .lineLimit(1)
            if let episode = entry.latestEpisode {
                Text("New: \(episode.seasonEpisodeLabel ?? episode.title)")
                    .font(.caption2)
                    .lineLimit(1)
            } else if let year = entry.pick?.movie.year {
                Text(String(year))
                    .font(.caption2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview(as: .systemMedium) {
    SpinOfTheDayWidget()
} timeline: {
    SpinOfTheDayEntry.sample
}

#Preview(as: .systemLarge) {
    SpinOfTheDayWidget()
} timeline: {
    SpinOfTheDayEntry.sample
}
