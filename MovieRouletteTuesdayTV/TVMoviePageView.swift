import SwiftUI
import MRTCore
import MRTShared

/// Movie page (mockup 08). Where-to-watch tries provider apps. Stars: swipe changes,
/// click submits the personal rating and the anonymous listener rating.
/// Poll, watchlist, and Suggest live in the right column. The tab bar stays hidden.
struct TVMoviePageView: View {
    let movie: Movie
    let catalog: MovieCatalog?
    let episodesByGUID: [String: PodcastEpisode]
    var breadcrumb: String
    var onSuggest: () -> Void
    var onBack: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL
    @Environment(PersonalRatingsStore.self) private var personal
    @Environment(CommunityService.self) private var community
    @FocusState private var providerFocus: Int?
    @State private var providerNote: String?
    @State private var savedNote: String?

    private var theme: TVTheme { TVTheme(scheme: scheme) }
    private var providers: [StreamingInfo.Provider] {
        TVProviderLaunching.tiles(for: movie, includeRentals: true, limit: 6)
    }
    private var episode: PodcastEpisode? {
        movie.episodeIds.compactMap { episodesByGUID[$0] }.first
    }
    private var poll: PollDefinition? {
        guard let guid = movie.episodeIds.first else { return nil }
        return community.poll(forEpisode: guid, show: catalog?.showInfo ?? .mrt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TVBackHeader(title: breadcrumb, action: onBack)
            HStack(alignment: .top, spacing: 56) {
                leftColumn
                rightColumn
                    .frame(width: 520)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 80)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tv.screen.movie")
        .defaultFocus($providerFocus, providers.first?.id)
        .onExitCommand(perform: onBack)
        .task(id: movie.id) { await community.loadRating(movieId: movie.id) }
        .task(id: poll?.id) {
            if let poll { await community.loadPoll(poll) }
        }
        .onAppear {
            if providerNote == nil { providerNote = providers.first.map { TVProviderLaunching.launch(for: $0, movie: movie).hint } }
            TVFocus.soon { if providerFocus == nil { providerFocus = providers.first?.id } }
        }
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(movie.title)
                .font(.system(size: 72, weight: .bold))
                .foregroundStyle(theme.text)
                .lineLimit(2)
                .minimumScaleFactor(0.45)
                .accessibilityIdentifier("tv.movie.title")
            HStack(spacing: 16) {
                Text("\(movie.year) · \(movie.genre)")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(theme.secondary)
                ForEach(movie.categories, id: \.self) { id in
                    if let category = catalog?.category(withId: id) {
                        TVCategoryChip(category: category, text: category.displayName, size: 26)
                    }
                }
            }
            if let title = movie.episodeTitle ?? episode?.title {
                Text("Discussed in the episode “\(title)”")
                    .font(.system(size: 28))
                    .foregroundStyle(theme.secondary)
                    .lineLimit(2)
            }
            whereToWatch
            HStack(alignment: .top, spacing: 20) {
                listenerCard
                ratingCard
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var whereToWatch: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Where to watch")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(theme.secondary)
            if providers.isEmpty {
                Text(WhereToWatchDisplay.emptyMessage)
                    .font(.system(size: 28))
                    .foregroundStyle(theme.secondary)
                    .accessibilityIdentifier("tv.movie.streamingEmpty")
            } else {
                HStack(spacing: 18) {
                    ForEach(providers, id: \.id) { provider in
                        TVProviderButton(provider: provider, movie: movie, side: 118) { launch in
                            providerNote = launch.hint
                            TVOpen.first(of: launch.urls, with: openURL, failure: "Couldn’t open \(launch.appName).") {
                                providerNote = $0
                            }
                        }
                        .focused($providerFocus, equals: provider.id)
                    }
                }
                .focusSection()
                Text(providerCaption)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(theme.secondary)
                    .accessibilityIdentifier("tv.movie.providerHint")
            }
        }
        .padding(.top, 8)
        .accessibilityIdentifier("tv.movie.whereToWatch")
        .onChange(of: providerFocus) { _, id in
            guard let id, let provider = providers.first(where: { $0.id == id }) else { return }
            providerNote = TVProviderLaunching.launch(for: provider, movie: movie).hint
        }
    }

    private var providerCaption: String {
        providerNote ?? "Select a service to open its app"
    }

    private var listenerCard: some View {
        let aggregate = community.ratingAggregates[movie.id]
        return VStack(alignment: .leading, spacing: 8) {
            Text("LISTENER AVERAGE")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(theme.secondary)
            if let aggregate, let average = aggregate.average {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(average, format: .number.precision(.fractionLength(1)))
                        .font(.system(size: 64, weight: .bold))
                        .foregroundStyle(theme.text)
                    Image(systemName: "star.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(Brand.jackpotGold)
                }
                Text(aggregate.count == 1 ? "1 rating" : "\(aggregate.count) ratings")
                    .font(.system(size: 24))
                    .foregroundStyle(theme.secondary)
            } else if community.errors[movie.id] != nil {
                Text("Couldn’t load listener ratings")
                    .font(.system(size: 28))
                    .foregroundStyle(theme.secondary)
            } else if aggregate == nil {
                Text("Loading…")
                    .font(.system(size: 28))
                    .foregroundStyle(theme.secondary)
            } else {
                Text("No listener ratings yet")
                    .font(.system(size: 28))
                    .foregroundStyle(theme.secondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(theme.card))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tv.movie.listenerAverage")
    }

    private var ratingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YOUR RATING")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(theme.secondary)
            TVStarRater(movieId: movie.id) { note in savedNote = note }
            Text(savedNote ?? "Swipe to change · Click to submit")
                .font(.system(size: 22))
                .foregroundStyle(theme.secondary)
                .lineLimit(2)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(theme.card))
        .accessibilityIdentifier("tv.movie.yourRating")
    }

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let poll {
                TVPollCard(poll: poll)
            }
            watchlistButton
            Button(action: onSuggest) {
                HStack(spacing: 18) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 36, weight: .semibold))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Suggest a movie")
                            .font(.system(size: 32, weight: .bold))
                        Text("Scan on your phone")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(theme.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 24, weight: .bold))
                }
            }
            .buttonStyle(TVRowButtonStyle())
            .accessibilityIdentifier("tv.movie.suggest")
        }
    }

    private var watchlistButton: some View {
        let onList = personal.status(for: movie.id) == .wantToWatch
        return Button {
            if onList {
                let rated = personal.halfStars(for: movie.id) != nil
                personal.setStatus(rated ? .watched : nil, for: movie.id)
            } else {
                personal.setStatus(.wantToWatch, for: movie.id)
            }
        } label: {
            Label(onList ? "On Watchlist" : "Add to Watchlist", systemImage: onList ? "checkmark" : "plus")
                .font(.system(size: 34, weight: .bold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(TVPillButtonStyle(primary: false, width: 520, height: 100, fontSize: 34))
        .accessibilityIdentifier("tv.movie.watchlist")
        .accessibilityValue(onList ? "On" : "Off")
    }
}

/// Five stars. Moving focus previews the rating; Select saves it on this Apple TV
/// and submits it as the anonymous listener rating.
private struct TVStarRater: View {
    let movieId: String
    var onNote: (String) -> Void

    @Environment(PersonalRatingsStore.self) private var personal
    @Environment(CommunityService.self) private var community
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focused: Int?

    private var savedStars: Int {
        personal.halfStars(for: movieId).map { HalfStars.roundedStars($0) } ?? 0
    }

    var body: some View {
        let shown = focused ?? savedStars
        VStack(alignment: .leading, spacing: 0) {
            // tvOS drops an identifier on the star HStack. This sibling is the
            // row the tests look up; each star stays its own focusable button.
            Color.clear
                .frame(width: 280, height: 8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Your rating")
                .accessibilityIdentifier("tv.movie.stars")
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { star in
                    Button { submit(star) } label: {
                        Image(systemName: star <= shown ? "star.fill" : "star")
                            .font(.system(size: 40))
                            .foregroundStyle(star <= shown ? Brand.jackpotGold : TVTheme(scheme: scheme).secondary)
                            .frame(width: 56, height: 56)
                    }
                    .buttonStyle(TVPlainButtonStyle())
                    .focused($focused, equals: star)
                    .accessibilityLabel("\(star) \(star == 1 ? "star" : "stars")")
                    .accessibilityHint("Saves your rating and shares it with listeners")
                    .accessibilityIdentifier("tv.movie.star.\(star)")
                }
            }
        }
    }

    private func submit(_ stars: Int) {
        let half = stars * 2
        personal.setHalfStars(half, for: movieId)
        onNote("Saving…")
        Task {
            await community.submitListenerRating(movieId: movieId, halfStars: half)
            if let error = community.errors[movieId] {
                onNote("Saved on this Apple TV. \(error)")
            } else if community.accountStatus.canWrite {
                onNote("Saved on this Apple TV and shared with listeners")
            } else {
                onNote("Saved on this Apple TV. \(community.accountMessage ?? "Sign in to iCloud to share it.")")
            }
        }
    }
}

private struct TVPollCard: View {
    let poll: PollDefinition
    @Environment(CommunityService.self) private var community
    @Environment(\.colorScheme) private var scheme

    private var theme: TVTheme { TVTheme(scheme: scheme) }
    private var myVote: String? { community.myVote(for: poll) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("EPISODE POLL")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(theme.teal)
            Text(poll.question)
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)
            if community.canSeeResults(poll), let results = community.pollResults[poll.id] {
                ForEach(results.rows, id: \.option.id) { row in
                    resultRow(row)
                }
                Text(results.total == 1 ? "1 vote" : "\(results.total) votes")
                    .font(.system(size: 24))
                    .foregroundStyle(theme.secondary)
            } else {
                ForEach(poll.options) { option in
                    Button {
                        Task { await community.vote(poll, option: option) }
                    } label: {
                        Text(option.label)
                            .font(.system(size: 30, weight: .semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(TVRowButtonStyle())
                    .disabled(!community.accountStatus.canWrite || community.busy.contains(poll.id))
                    .accessibilityIdentifier("tv.poll.\(option.id)")
                }
                Text(community.accountMessage ?? "Results appear after you vote")
                    .font(.system(size: 24))
                    .foregroundStyle(theme.secondary)
            }
            if let error = community.errors[poll.id] {
                Text(error)
                    .font(.system(size: 24))
                    .foregroundStyle(.orange)
            }
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(theme.card))
        .accessibilityIdentifier("tv.movie.poll")
    }

    private func resultRow(_ row: PollResults.Row) -> some View {
        let mine = row.option.id == myVote
        return Button {
            guard !mine else { return }
            Task { await community.vote(poll, option: row.option) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(row.option.label)
                        .font(.system(size: 28, weight: mine ? .bold : .regular))
                    if mine {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Brand.teal)
                    }
                    Spacer()
                    Text(row.fraction, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 28, weight: .semibold))
                }
                ProgressView(value: row.fraction)
                    .tint(mine ? Brand.teal : Brand.peach)
            }
        }
        .buttonStyle(TVRowButtonStyle())
        .accessibilityIdentifier("tv.poll.\(row.option.id)")
    }
}
