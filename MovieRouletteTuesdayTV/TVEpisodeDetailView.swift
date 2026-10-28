import SwiftUI
import MRTCore
import MRTShared

/// Episode page (mockup 06). Listen opens Apple Podcasts. The tab bar stays hidden.
struct TVEpisodeDetailView: View {
    let episode: PodcastEpisode
    let catalog: MovieCatalog?
    let showArtworkURL: URL?
    var showsNew = false
    var onOpenMovie: (Movie) -> Void
    var onBack: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL
    @State private var openNote: String?
    @FocusState private var focus: Control?

    private enum Control: Hashable { case listen, movie }
    private var theme: TVTheme { TVTheme(scheme: scheme) }
    private var show: ShowInfo { catalog?.showInfo ?? .mrt }
    private var movie: Movie? { catalog?.movie(forEpisodeGuid: episode.guid) }
    private var apple: AppleEpisodeLinks { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            TVBackHeader(title: "Episodes", action: onBack)
            HStack(alignment: .center, spacing: 72) {
                ArtworkImage(
                    urls: ArtworkResolver.candidates(for: episode, showArtwork: showArtworkURL),
                    pointSize: 560,
                    cornerRadius: 36,
                    placeholderSymbol: "mic"
                )
                .frame(width: 520, height: 520)
                .shadow(color: .black.opacity(0.35), radius: 24, y: 14)
                details
            }
            Spacer(minLength: 0)
            Text("MENU Back to Episodes")
                .font(.system(size: 26))
                .foregroundStyle(theme.secondary)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 80)
        .padding(.top, 36)
        .padding(.bottom, 28)
        .accessibilityIdentifier("tv.screen.episode")
        .defaultFocus($focus, .listen)
        .onAppear { focus = .listen }
        .onExitCommand(perform: onBack)
        .task(id: episode.guid) { await apple.ensure(guid: episode.guid, show: show) }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                if showsNew {
                    Text("NEW")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Brand.tealDark))
                }
                Text(TVFormat.episodeMeta(episode))
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(theme.secondary)
            }
            Text(episode.title)
                .font(.system(size: 84, weight: .bold))
                .foregroundStyle(theme.text)
                .lineLimit(3)
                .minimumScaleFactor(0.5)
                .accessibilityIdentifier("tv.episode.title")
            if let movie {
                HStack(spacing: 14) {
                    ForEach(movie.categories, id: \.self) { id in
                        if let category = catalog?.category(withId: id) {
                            TVCategoryChip(category: category, text: category.displayName, size: 28)
                        }
                    }
                }
            }
            Text(episode.displaySummary)
                .font(.system(size: 32))
                .foregroundStyle(theme.secondary)
                .lineLimit(6)
            HStack(spacing: 28) {
                Button(action: listen) {
                    Label("Listen", systemImage: "play.fill")
                }
                .buttonStyle(TVPillButtonStyle(width: 420, height: 112))
                .focused($focus, equals: .listen)
                .accessibilityIdentifier("tv.episode.listen")
                if let movie {
                    Button { onOpenMovie(movie) } label: { Text("Movie Page") }
                        .buttonStyle(TVPillButtonStyle(primary: false, width: 380, height: 112))
                        .focused($focus, equals: .movie)
                        .accessibilityIdentifier("tv.episode.movie")
                }
            }
            .padding(.top, 8)
            .focusSection()
            Label(openNote ?? "Opens in Apple Podcasts", systemImage: "apple.logo")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(theme.secondary)
                .accessibilityIdentifier("tv.episode.listenHint")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func listen() {
        let link = apple.link(forGUID: episode.guid, show: show)
        guard let url = link?.url ?? PodcastLinks.appleShow(show: show) else {
            openNote = "Apple Podcasts isn’t available for this episode."
            return
        }
        openNote = link?.isExactEpisode == false
            ? "Opens the show in Apple Podcasts"
            : "Opens in Apple Podcasts"
        TVOpen.first(of: [url], with: openURL, failure: "Couldn’t open Apple Podcasts.") { openNote = $0 }
    }
}
