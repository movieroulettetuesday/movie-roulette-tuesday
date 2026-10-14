import SwiftUI

/// Gear in the Roulette toolbar.
struct SettingsSheet: View {
    @AppStorage(AppSettings.tickSound) private var tickSound = true
    @AppStorage(AppSettings.haptics) private var haptics = true
    @AppStorage(AppSettings.rareOutcomes) private var rareOutcomes = true
    @AppStorage(AppSettings.autoShareRatings) private var autoShareRatings = false
    @AppStorage(AppearancePreference.storageKey) private var appearance = AppearancePreference.default.rawValue
    @AppStorage(NewEpisodeAlerts.enabledKey) private var newEpisodeAlerts = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    /// For the suggestion form's optional category picker.
    var categories: [RouletteCategory] = []
    /// Newest episodes the app already shows (baseline for alerts).
    var knownEpisodes: [PodcastEpisode] = []
    @State private var showsSuggest = false
    @State private var alertNote: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: alertsBinding) {
                        Label("New-episode alert", systemImage: "bell.badge")
                    }
                    .accessibilityIdentifier("settings-new-episode-alert")
                    if let alertNote {
                        Text(alertNote)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("settings-alert-note")
                    }
                } header: {
                    Text("New Episodes")
                } footer: {
                    Text("Off by default. When on, the app occasionally checks the show’s public RSS feed in the background and notifies you about a new episode. iOS decides when that check runs, so alerts can arrive hours late. No account, no server; notification permission is asked only when you turn this on.")
                }

                Section {
                    ForEach(FollowTheShow.links()) { link in
                        Link(destination: link.url) {
                            HStack(spacing: 12) {
                                Image(systemName: link.symbol)
                                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .background(Color(hex: link.tileHex), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                Text(link.title).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "arrow.up.forward").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                        }
                        .tint(.primary) // mockup: primary text, not the accent tint
                        .accessibilityHint("Opens outside the app")
                    }
                } header: {
                    Text("Follow the Show")
                } footer: {
                    Text("Opens in the app or your browser. Nothing about you is shared.")
                }

                Section {
                    Button {
                        showsSuggest = true
                    } label: {
                        HStack {
                            Label("Suggest a movie", systemImage: "envelope")
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .foregroundStyle(.primary)
                    }
                    .tint(.primary)
                    .accessibilityIdentifier("settings-suggest")
                } footer: {
                    Text("Emails \(MovieSuggestion.address), or send it in the app.")
                }

                Section {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppearancePreference.allCases) { option in
                            Text(option.label).tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("System follows your iPhone's Light/Dark setting.")
                }

                Section {
                    Toggle("Spin sound", isOn: $tickSound)
                    Toggle("Haptics", isOn: $haptics)
                } header: {
                    Text("Spin")
                } footer: {
                    Text("A real wheel clicks as each slice passes the pointer. It follows your Ring/Silent switch.")
                }

                Section {
                    Toggle("Rare outcomes", isOn: $rareOutcomes)
                } footer: {
                    Text("About 1 spin in 100 is a “Re-spin forced!”, and about 1 in 100 hits the Infamous Jackpot (only when the movie list has infamous picks).")
                }

                Section {
                    Toggle("Auto-share my star ratings", isOn: $autoShareRatings)
                } header: {
                    Text("Listener Ratings")
                } footer: {
                    Text("When on, rating a movie also adds your stars to the anonymous listener average (needs iCloud). When off, you can still add them movie by movie.")
                }

                Section("Privacy") {
                    Text(AppSettings.privacyNote)
                        .font(.callout)
                }
            }
            .cleanProListScreen()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showsSuggest) {
                SuggestMovieSheet(categories: categories)
                    .presentationDetents([.fraction(0.62), .large])
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// Permission is requested only when the user turns the alert on; if it's
    /// refused, the toggle goes back off and a note explains why.
    private var alertsBinding: Binding<Bool> {
        Binding(
            get: { newEpisodeAlerts },
            set: { on in
                alertNote = nil
                guard on else {
                    newEpisodeAlerts = false
                    NewEpisodeAlerts.cancel()
                    return
                }
                newEpisodeAlerts = true
                Task { @MainActor in
                    if await NewEpisodeAlerts.requestPermission() {
                        // Today's episodes are the baseline; only later ones alert.
                        // Feed not loaded yet: drop any old marker so the first
                        // check sets a fresh baseline instead of alerting on
                        // everything since the alert was last on.
                        if knownEpisodes.isEmpty { NewEpisodeAlerts.resetWatermark() }
                        NewEpisodeAlerts.markSeen(knownEpisodes)
                        NewEpisodeAlerts.scheduleIfEnabled()
                    } else {
                        newEpisodeAlerts = false
                        alertNote = "Notifications are off for Movie Roulette Tuesday. Allow them in the Settings app (Notifications), then turn this on again."
                    }
                }
            }
        )
    }
}

#Preview {
    SettingsSheet()
}
