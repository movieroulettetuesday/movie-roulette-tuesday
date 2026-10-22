import SwiftUI
import MRTCore
import MRTShared

/// Bottom sheet shown after the wheel stops.
struct RevealSheet: View {
    let reveal: RouletteViewModel.Reveal
    let catalog: MovieCatalog?
    var episodesByGUID: [String: PodcastEpisode] = [:]
    var showArtworkURL: URL? = nil
    let onSpinAgain: () -> Void
    /// True when presented from a regular-width window (iPad): a full form
    /// sheet instead of the iPhone's partial-height detent.
    var presenterIsRegularWidth = false

    @State private var shareImage: Image?
    @Environment(\.colorScheme) private var colorScheme

    private var movie: Movie { reveal.movie }
    private var episodeText: String {
        EpisodeLabel.discussedText(for: movie, episodesByGUID: episodesByGUID)
    }

    private var spinCountText: String {
        reveal.spinCount == 1
            ? "First spin"
            : "Spun \(reveal.spinCount) times"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CleanPro.spacing) {
                    summaryCard
                    VStack(spacing: 12) {
                        // Same bordered family as Share / Movie Page (no SPIN pill anywhere
                        // now; the hub is the spin button). Teal, full width, it leads.
                        Button(action: onSpinAgain) {
                            Label("Spin again", systemImage: "arrow.clockwise")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Brand.tealDark)
                        .controlSize(.large)

                        HStack(spacing: 12) {
                            shareButton
                            // Value route (not a view-destination link): the episode links on the
                            // pushed movie page are value routes too, and only resolve when the
                            // whole chain is value-based, as in the Movies tab and Spin History.
                            NavigationLink(value: MoviesRoute.movie(movie.id)) {
                                Label("Movie page", systemImage: "film")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            // Episodes rows on the pushed movie page (same page as the Episodes tab / Spin History).
            // Movie Page and its Episodes rows (same pages as the Movies tab / Spin History).
            .navigationDestination(for: MoviesRoute.self) { destination(for: $0) }
            .background {
                if reveal.isJackpot {
                    LinearGradient(colors: CleanProColors.backgroundDark.map { Color(hex: $0) },
                                   startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()
                } else {
                    CleanProBackground()
                }
            }
            .environment(\.colorScheme, reveal.isJackpot ? .dark : colorScheme)
            .overlay {
                ConfettiView()
                    .ignoresSafeArea()
            }
            .navigationTitle(reveal.isJackpot ? "Infamous Jackpot" : "Tonight’s Movie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Jackpot: the gold banner *is* the bar title (navigationTitle stays for the back button / VoiceOver).
                if reveal.isJackpot {
                    ToolbarItem(placement: .principal) { jackpotBanner }
                }
            }
        }
        .onAppear {
            // ImageRenderer must run on the main actor; the card is small and local-only.
            if shareImage == nil {
                shareImage = ShareCardRenderer.image(for: reveal, episodeText: episodeText)
            }
        }
        .presentationDetents(presenterIsRegularWidth ? [.large] : [.fraction(0.65), .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func destination(for route: MoviesRoute) -> some View {
        switch route {
        case .movie(let id):
            if let page = id == movie.id ? movie : catalog?.movie(withId: id) {
                MoviePageView(
                    movie: page,
                    catalog: catalog,
                    episodesByGUID: episodesByGUID,
                    showArtworkURL: showArtworkURL,
                    context: .wheelReveal
                )
            } else {
                ContentUnavailableView("Movie Not Found", systemImage: "film")
            }
        case .episode(let guid):
            if let episode = episodesByGUID[guid] {
                EpisodeDetailView(
                    episode: episode,
                    catalog: catalog,
                    show: catalog?.showInfo ?? .mrt,
                    showArtworkURL: showArtworkURL
                )
            } else {
                ContentUnavailableView("Episode Not Found", systemImage: "mic.slash")
            }
        }
    }

    private var summaryCard: some View {
        VStack(spacing: 12) {
            categoryChip

            Text(movie.title)
                .font(.largeTitle.bold())
                .foregroundStyle(reveal.isJackpot ? Brand.jackpotGold : .primary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.6)

            // verbatim: avoid locale grouping ("1,988").
            Text(verbatim: catalog?.subtitle(for: movie) ?? "\(movie.year) · \(movie.genre)")
                .font(.headline)
                .foregroundStyle(.secondary)

            Label(episodeText, systemImage: "mic.fill")
                .font(.subheadline)
                .multilineTextAlignment(.center)

            Text(spinCountText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .cleanProCard(padding: 20)
    }

    @ViewBuilder
    private var shareButton: some View {
        if let shareImage {
            ShareLink(
                item: shareImage,
                subject: Text(movie.title),
                message: Text(verbatim: "Tonight’s Movie Roulette Tuesday spin: \(movie.title) (\(movie.year))"),
                preview: SharePreview(movie.title, image: shareImage)
            ) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Brand.accentTeal)
            .controlSize(.large)
        }
    }

    private var jackpotBanner: some View {
        Text("Infamous Jackpot")
            .font(.headline.weight(.black))
            .fontDesign(.rounded)
            .tracking(0.5)
            .foregroundStyle(Brand.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Brand.jackpotGold, in: Capsule())
            .accessibilityLabel("Infamous jackpot")
    }

    private var categoryChip: some View {
        Text(reveal.category.name.uppercased())
            .font(.caption.weight(.bold))
            .tracking(1)
            .foregroundStyle(Color.labelColor(onHex: reveal.category.displayHex))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(hex: reveal.category.displayHex), in: Capsule())
    }
}

#Preview {
    Text("Wheel")
        .sheet(isPresented: .constant(true)) {
            RevealSheet(
                reveal: .init(
                    id: UUID(),
                    movie: Movie(id: "the-room-2003", title: "The Room", year: 2003, genre: "Drama",
                                 categories: ["cat-cult-classics"], episodeIds: ["sample-ep-6"]),
                    category: RouletteCategory(id: "cat-cult", name: "Cult", colorHex: "#7B2CBF"),
                    spinCount: 1
                ),
                catalog: nil,
                onSpinAgain: {}
            )
            .environment(PersonalRatingsStore(fileStore: nil))
            .environment(SpinHistoryStore(fileStore: nil))
            .environment(CommunityService.preview())
        }
}
