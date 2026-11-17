import SwiftUI

struct RulesSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// iPad (regular-width presenter): full form sheet, no partial detent.
    var presenterIsRegularWidth = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(HouseRules.sections) { section in
                    Section {
                        ForEach(section.rows) { row in
                            label(for: row)
                                .accessibilityIdentifier("house-rules-row-\(row.id)")
                        }
                    } header: {
                        if let title = section.title {
                            Text(title)
                                .accessibilityIdentifier("house-rules-section-\(section.id)")
                        }
                    } footer: {
                        if let footer = section.footer {
                            Text(footer)
                        }
                    }
                    .labelStyle(RuleLabelStyle())
                }
            }
            .cleanProListScreen()
            .accessibilityIdentifier("house-rules-list")
            .navigationTitle("House Rules")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: {
                        Label("Done", systemImage: "checkmark")
                    }
                }
            }
        }
        .presentationDetents(presenterIsRegularWidth ? [.large] : [.medium, .large])
    }

    @ViewBuilder
    private func label(for row: HouseRules.Row) -> some View {
        switch row.icon {
        case .asset(let name): Label(row.text, image: name)
        case .system(let name): Label(row.text, systemImage: name)
        }
    }
}

/// Teal icon column + generous row padding (Clean Pro list rows).
private struct RuleLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            configuration.icon
                .foregroundStyle(Brand.accentTeal)
                .frame(minWidth: 24)
            configuration.title
        }
        .padding(.vertical, 6)
    }
}

/// Everything House Rules says, as data. The Siri list mirrors
/// `MovieRouletteShortcuts` and the Shortcuts list mirrors the discoverable
/// App Intents; unit tests compare both with the compiled App Intents
/// metadata, so a renamed or new phrase fails a test until it's listed here.
enum HouseRules {
    /// What `\(.applicationName)` is spoken as (INAlternativeAppNames).
    static let spokenAppName = "Movie Roulette"

    enum Icon: Equatable {
        case asset(String)
        case system(String)
    }

    struct Row: Identifiable, Equatable {
        var id: String
        var text: String
        var icon: Icon
    }

    struct Section: Identifiable, Equatable {
        var id: String
        var title: String?
        var rows: [Row]
        var footer: String?
    }

    /// One App Shortcut: its intent's type name, its phrase templates exactly as
    /// the App Intents metadata spells them, and what it does.
    struct SiriShortcut: Equatable {
        var intent: String
        var phrases: [String]
        var does: String
        var systemImage: String
    }

    static let siriShortcuts: [SiriShortcut] = [
        SiriShortcut(
            intent: "SpinMovieRouletteIntent",
            phrases: ["Spin ${applicationName}", "Spin the wheel in ${applicationName}"],
            does: "spins the wheel and opens the result.",
            systemImage: "dial.medium"
        ),
        SiriShortcut(
            intent: "WhatShouldIWatchIntent",
            phrases: ["Pick a movie for me in ${applicationName}", "What should I watch in ${applicationName}"],
            does: "picks one movie you haven’t watched and says why. Not random.",
            systemImage: "sparkles"
        ),
        SiriShortcut(
            intent: "OpenMovieIntent",
            phrases: ["Open ${movie} in ${applicationName}"],
            does: "opens that movie’s page.",
            systemImage: "film"
        ),
        SiriShortcut(
            intent: "FindMovieIntent",
            phrases: ["Find ${movie} in ${applicationName}", "Search ${applicationName} for ${movie}", "Find a movie in ${applicationName}"],
            does: "finds a movie by title, year, episode (like S4E39), genre or service.",
            systemImage: "magnifyingglass"
        ),
        SiriShortcut(
            intent: "LatestEpisodeIntent",
            phrases: ["Latest episode of ${applicationName}", "What's the latest ${applicationName} episode"],
            does: "opens the newest episode and offers to play it in Podcasts.",
            systemImage: "mic"
        ),
        SiriShortcut(
            intent: "ShowWatchlistIntent",
            phrases: ["What's on my ${applicationName} watchlist", "Show my ${applicationName} watchlist"],
            does: "lists the movies you marked Want to watch.",
            systemImage: "bookmark"
        ),
        SiriShortcut(
            intent: "AddToWatchlistIntent",
            phrases: ["Add ${movie} to my ${applicationName} watchlist"],
            does: "puts a movie on your watchlist. Your rating doesn’t change.",
            systemImage: "plus.circle"
        ),
        SiriShortcut(
            intent: "MarkWatchedIntent",
            phrases: ["Mark ${movie} as watched in ${applicationName}"],
            does: "marks a movie watched without adding a rating.",
            systemImage: "checkmark.circle"
        ),
        SiriShortcut(
            intent: "WhereToWatchIntent",
            phrases: ["Where can I watch ${movie} in ${applicationName}"],
            does: "says where a movie is streaming, your services first.",
            systemImage: "tv"
        ),
        SiriShortcut(
            intent: "OpenOnProviderIntent",
            phrases: ["Open ${movie} on a service in ${applicationName}", "Open a movie on ${provider} in ${applicationName}"],
            does: "opens a movie in a streaming app, or on the web if the app isn’t installed. Siri asks for the movie or service you didn’t say.",
            systemImage: "arrow.up.right.square"
        ),
    ]

    /// Titles of the discoverable App Intents, as the Shortcuts app shows them.
    static let shortcutsActions: [String] = [
        "Spin Movie Roulette", "Pick for Me", "Open Movie", "Find Movie", "Find Episode",
        "Latest Episode", "Show Watchlist", "Add to Watchlist", "Mark Watched",
        "Where to Watch", "Open on Provider",
    ]

    /// "Open ${movie} in ${applicationName}" → "Open [movie] in Movie Roulette".
    static func spoken(_ template: String) -> String {
        template
            .replacingOccurrences(of: "${applicationName}", with: spokenAppName)
            .replacingOccurrences(of: "${movie}", with: "[movie]")
            .replacingOccurrences(of: "${provider}", with: "[service]")
            .replacingOccurrences(of: "'", with: "’")
    }

    static func siriRowText(_ shortcut: SiriShortcut) -> String {
        let phrases = shortcut.phrases.map { "“\(spoken($0))”" }
        return phrases.joined(separator: " or ") + " " + shortcut.does
    }

    static var sections: [Section] {
        [
            Section(id: "wheel", title: "The Wheel", rows: [
                Row(id: "wheel-spin", text: "Tap the glowing hub, or anywhere on the wheel, to spin. While it spins, tap the ■ in the center to stop early.", icon: .asset("roulette.wheel")),
                Row(id: "wheel-arrow", text: "The arrow at the top picks a theme category, like Horror, Criterion, Love Hurts or Listener Picks.", icon: .system("arrowtriangle.down.fill")),
                Row(id: "wheel-movie", text: "Then a movie from that category is drawn. Recent spins are less likely to repeat, and every title was discussed on the show.", icon: .system("film.stack")),
            ]),
            Section(id: "pick", title: "Spin or Pick for Me", rows: [
                Row(id: "pick-spin", text: "Spin is pure chance: the wheel picks a category, then a movie from it.", icon: .system("dice")),
                Row(id: "pick-purpose", text: "Pick for Me is on purpose: it picks one you haven’t watched, favouring your watchlist and your services, and tells you why.", icon: .system("sparkles")),
                Row(id: "pick-reason", text: "The reason only says what the app knows: your watchlist, your ratings, and where it’s streaming.", icon: .system("checkmark.seal")),
                Row(id: "pick-device", text: "Runs on your device with Apple Intelligence. Nothing leaves your device. If your device can’t run it, the button is hidden.", icon: .system("lock")),
            ]),
            Section(id: "search", title: "Search", rows: [
                Row(id: "search-keywords", text: "Search Movies or Episodes by title, year, episode (S4E39), genre or service.", icon: .system("magnifyingglass")),
                Row(id: "search-questions", text: "Or ask a question, like “comedies from the 90s on Netflix”. It becomes filter chips; tap a chip’s × to remove it.", icon: .system("text.bubble")),
                Row(id: "search-fallback", text: "Without Apple Intelligence, search matches keywords only.", icon: .system("textformat")),
            ]),
            Section(id: "lists", title: "Your Lists", rows: [
                Row(id: "lists-watchlist", text: "Want to watch puts a movie on your watchlist.", icon: .system("bookmark")),
                Row(id: "lists-rating", text: "Rating a movie marks it watched. You can clear a rating any time.", icon: .system("checkmark.circle")),
                Row(id: "lists-stars", text: "Tap the left half of a star for a half star, the right half for the whole star, or drag across the stars. Tap your rating again, or Clear rating, to remove it.", icon: .system("star.leadinghalf.filled")),
            ]),
            Section(
                id: "siri",
                title: "Siri and Shortcuts",
                rows: siriShortcuts.map { shortcut in
                    Row(id: "siri-\(shortcut.intent)", text: siriRowText(shortcut), icon: .system(shortcut.systemImage))
                } + [
                    Row(id: "shortcuts-actions", text: "In the Shortcuts app, add Movie Roulette actions to your own shortcuts: " + shortcutsActions.joined(separator: ", ") + ".", icon: .system("square.stack.3d.up")),
                ],
                footer: "These work as soon as the app is installed. Say them to Siri or type them. Siri support depends on your device and language."
            ),
            Section(id: "widget", title: "Home Screen Widget", rows: [
                Row(id: "widget-what", text: "Spin of the Day shows today’s pick from the wheel (the same for everyone that day) and the latest episode. A new pick arrives at midnight. Tap it to open that movie.", icon: .system("square.grid.2x2")),
                Row(id: "widget-small", text: "Small: today’s pick, plus a line when there’s a new episode.", icon: .system("square")),
                Row(id: "widget-medium", text: "Medium: today’s pick beside the latest episode (or your last spin).", icon: .system("rectangle")),
                Row(id: "widget-large", text: "Large: today’s pick and its genre, the latest episode, and your last spin.", icon: .system("square.fill")),
                Row(id: "widget-lock", text: "Lock Screen: today’s pick and the newest episode, in the rectangular size.", icon: .system("lock.rectangle")),
                Row(id: "widget-add", text: "To add it, touch and hold the Home Screen, tap Edit, then Add Widget, and search Movie Roulette. For the Lock Screen, touch and hold the Lock Screen, tap Customize, then add a widget and choose Movie Roulette.", icon: .system("plus.square.on.square")),
            ]),
            Section(id: "good", title: "Good to Know", rows: [
                Row(id: "good-intelligence", text: "Pick for Me and question search use Apple Intelligence, so they depend on your device, its language and settings. Without it, the wheel, keyword search and Siri phrases still work.", icon: .system("info.circle")),
                Row(id: "good-spotlight", text: "Movies and episodes from the show appear in Spotlight. Swipe down on the Home Screen and type a title.", icon: .system("magnifyingglass.circle")),
                Row(id: "good-links", text: "Links that start with mrt:// open the app at a spin, a movie, an episode or the episode list, for example mrt://spin.", icon: .system("link")),
            ], footer: "Dinner, discussion, and the wheel. Spin responsibly."),
        ]
    }
}
