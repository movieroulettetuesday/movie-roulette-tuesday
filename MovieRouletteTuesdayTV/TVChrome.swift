import SwiftUI
import MRTCore
import MRTShared

/// The mockups' backdrop: Clean Pro gradient plus a faint teal glow, top right.
struct TVBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            LinearGradient(colors: CleanPro.backgroundColors(scheme), startPoint: .top, endPoint: .bottom)
            RadialGradient(
                colors: [Brand.teal.opacity(scheme == .dark ? 0.35 : 0.16), .clear],
                center: .topTrailing, startRadius: 0, endRadius: 900
            )
        }
        .ignoresSafeArea()
    }
}

enum TVFormat {
    /// Newest episode in the last three weeks (the row "NEW" badge and the tab dot).
    static let recentEpisodeWindow: TimeInterval = 21 * 24 * 60 * 60

    static func newestIsRecent(_ episodes: [PodcastEpisode], now: Date = Date()) -> Bool {
        guard let newest = episodes.max(by: { ($0.pubDate ?? .distantPast) < ($1.pubDate ?? .distantPast) }),
              let date = newest.pubDate else { return false }
        let age = now.timeIntervalSince(date)
        return age < recentEpisodeWindow && age > -24 * 60 * 60
    }

    static func showsNewBadge(_ episode: PodcastEpisode, in episodes: [PodcastEpisode], now: Date = Date()) -> Bool {
        guard let date = episode.pubDate else { return false }
        guard let newest = episodes.max(by: { ($0.pubDate ?? .distantPast) < ($1.pubDate ?? .distantPast) }),
              newest.guid == episode.guid else { return false }
        let age = now.timeIntervalSince(date)
        return age < recentEpisodeWindow && age > -24 * 60 * 60
    }

    static func runtime(_ seconds: TimeInterval?) -> String? {
        guard let seconds, seconds > 0, seconds.isFinite else { return nil }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return minutes == 0 ? "\(hours) hr" : "\(hours) hr \(minutes) min" }
        return "\(max(minutes, 1)) min"
    }

    static func mediumDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// "Tonight" / "Yesterday" / "Oct 24", matching the Stats mockup.
    static func spinWhen(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Tonight" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func episodeMeta(_ episode: PodcastEpisode) -> String {
        var parts: [String] = []
        if let label = episode.seasonEpisodeLabel { parts.append(label) }
        if let date = episode.pubDate { parts.append(mediumDate(date)) }
        if let runtime = runtime(episode.duration) { parts.append(runtime) }
        return parts.joined(separator: " · ")
    }

    static func sortedNewestFirst(_ episodes: [PodcastEpisode]) -> [PodcastEpisode] {
        episodes.sorted { a, b in
            switch (a.pubDate, b.pubDate) {
            case let (left?, right?): return left > right
            case (nil, _?): return false
            case (_?, nil): return true
            default: return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        }
    }
}

/// Loading, failure, and empty states shared by the TV tabs.
struct TVStatusView: View {
    var title: String
    var systemImage: String = "film"
    var message: String?
    var retryTitle: String?
    var retry: (() -> Void)?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = TVTheme(scheme: scheme)
        VStack(spacing: 28) {
            Image(systemName: systemImage)
                .font(.system(size: 72, weight: .semibold))
                .foregroundStyle(theme.teal)
            Text(title)
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(theme.text)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.system(size: 32))
                    .foregroundStyle(theme.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 980)
            }
            if let retryTitle, let retry {
                Button(retryTitle, action: retry)
                    .buttonStyle(TVPillButtonStyle(width: 420, height: 108, fontSize: 36))
                    .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Detail screens hide the tab bar and show a breadcrumb (mockups 06, 08, 10).
struct TVBackHeader: View {
    let title: String
    var action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 28, weight: .bold))
                Text(title)
                    .font(.system(size: 32, weight: .semibold))
            }
            .foregroundStyle(TVTheme(scheme: scheme).secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to \(title)")
        .accessibilityIdentifier("tv.back")
    }
}

enum TVFocus {
    /// tvOS puts the first focus on the tab bar. Move it into the tab on the next turn.
    @MainActor
    static func soon(_ apply: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            apply()
        }
    }
}

enum TVOpen {
    /// Tries each URL until one is accepted (provider app, then a web fallback).
    static func first(
        of urls: [URL],
        with openURL: OpenURLAction,
        failure: String,
        onFailure: @escaping (String) -> Void
    ) {
        guard let url = urls.first else { onFailure(failure); return }
        openURL(url) { accepted in
            Task { @MainActor in
                if accepted { return }
                let rest = Array(urls.dropFirst())
                if rest.isEmpty { onFailure(failure) }
                else { first(of: rest, with: openURL, failure: failure, onFailure: onFailure) }
            }
        }
    }
}

/// Screen title used by every tab (mockups: ~80 pt bold).
struct TVScreenTitle: View {
    let text: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Text(text)
            .font(.system(size: 76, weight: .bold))
            .foregroundStyle(TVTheme(scheme: scheme).text)
    }
}
