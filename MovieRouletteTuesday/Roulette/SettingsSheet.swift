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
    /// For My Services (providers found in the catalog).
    var movies: [Movie] = []
    @State private var showsSuggest = false
    @State private var alertNote: String?

    var body: some View {
        NavigationStack {
            Form {
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
                    Text("System follows your iPhone’s Light or Dark setting.")
                }

                Section {
                    Toggle(isOn: $tickSound) { SettingsRowLabel("Spin sound", symbol: "speaker.wave.2.fill") }
                    Toggle(isOn: $haptics) { SettingsRowLabel("Haptics", symbol: "iphone.radiowaves.left.and.right") }
                    Toggle(isOn: $rareOutcomes) { SettingsRowLabel("Rare outcomes", symbol: "sparkles") }
                } header: {
                    Text("Spin")
                } footer: {
                    Text("Sound follows your Ring/Silent switch.")
                }

                Section {
                    Toggle(isOn: alertsBinding) {
                        SettingsRowLabel("New-episode alert", symbol: "bell.badge.fill")
                    }
                    .accessibilityIdentifier("settings-new-episode-alert")
                    if let alertNote {
                        Text(alertNote)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("settings-alert-note")
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Checks for new episodes in the background, so alerts can arrive late.")
                }

                Section {
                    NavigationLink {
                        MyServicesView(providers: StreamingCatalog.services(in: movies))
                    } label: {
                        SettingsRowLabel("My services", symbol: "play.tv.fill")
                    }
                    .accessibilityIdentifier("settings-my-services")
                } header: {
                    Text("Where to Watch")
                } footer: {
                    Text("Choose your streaming services to filter the Movies tab.")
                }

                Section {
                    Toggle(isOn: $autoShareRatings) { SettingsRowLabel("Auto-share my ratings", symbol: "person.3.fill") }
                } header: {
                    Text("Listener Ratings")
                } footer: {
                    Text("Shares your star ratings anonymously with other listeners (needs iCloud).")
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
                }

                Section {
                    Button {
                        showsSuggest = true
                    } label: {
                        HStack {
                            SettingsRowLabel("Suggest a movie for the show", symbol: "envelope.fill")
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .foregroundStyle(.primary)
                    }
                    .tint(.primary)
                    .accessibilityIdentifier("settings-suggest")
                } footer: {
                    Text("Send the hosts a pick for a future episode.")
                }

                Section {
                    NavigationLink {
                        CreditsView()
                    } label: {
                        SettingsRowLabel("Credits & About", symbol: "info.circle.fill")
                    }
                    .accessibilityIdentifier("settings-credits")
                } header: {
                    Text("About")
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

/// Settings row label: a 28 pt teal tile with a white glyph (same size as the
/// Follow the Show tiles), so every Settings row reads the same.
struct SettingsRowLabel: View {
    let title: String
    let symbol: String
    init(_ title: String, symbol: String) { self.title = title; self.symbol = symbol }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Brand.tealDark, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
            Text(title)
        }
    }
}

/// Settings › My Services (approved mockup 6b): multi-select of the
/// providers that appear in the catalog, saved in UserDefaults.
struct MyServicesView: View {
    let providers: [StreamingInfo.Provider]
    @AppStorage(MyServices.storageKey) private var raw = ""

    var body: some View {
        let selected = MyServices(serialized: raw)
        List {
            if providers.isEmpty {
                Text("Streaming info isn’t available yet.")
                    .foregroundStyle(.secondary)
            } else {
                Section {
                    ForEach(providers, id: \.id) { p in
                        Button {
                            var s = MyServices(serialized: raw)
                            s.toggle(p.id)
                            raw = s.serialized
                        } label: {
                            HStack(spacing: 12) {
                                ProviderLogo(provider: p, size: 36)
                                Text(p.name).foregroundStyle(.primary)
                                Spacer()
                                if selected.contains(p.id) {
                                    Image(systemName: "checkmark").foregroundStyle(Brand.teal)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected.contains(p.id) ? .isSelected : [])
                        .accessibilityIdentifier("service-\(p.id)")
                    }
                } footer: {
                    Text(StreamingCatalog.attribution)
                }
            }
        }
        .cleanProListScreen()
        .navigationTitle("My Services")
    }
}

/// Credits & About: TMDB attribution (required by the TMDB API terms).
struct CreditsView: View {
    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    TMDBMark()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("The Movie Database (TMDB)").font(.headline)
                        Text("Streaming availability").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                Text(StreamingCatalog.tmdbNotice)
                    .font(.callout)
                    .accessibilityIdentifier("tmdb-notice")
                Text(StreamingCatalog.attribution + ".")
                    .font(.callout)
                if let url = URL(string: "https://www.themoviedb.org") {
                    Link("themoviedb.org", destination: url)
                }
            } header: { Text("Streaming Data") }
            Section {
                Text("The official companion app from the hosts of Movie Roulette Tuesday: The Podcast.")
                    .font(.callout)
                Text("Version \(AppSettings.versionString)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("about-version")
            } header: { Text("About") }
        }
        .cleanProListScreen()
        .navigationTitle("Credits & About")
    }
}

/// TMDB wordmark in TMDB's brand colors (drawn, no bundled asset).
private struct TMDBMark: View {
    var body: some View {
        Text("TMDB")
            .font(.system(size: 15, weight: .heavy, design: .rounded))
            .foregroundStyle(LinearGradient(colors: [Color(hex: "#90CEA1"), Color(hex: "#01B4E4")],
                                            startPoint: .leading, endPoint: .trailing))
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color(hex: "#0D253F"), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityLabel("TMDB logo")
    }
}

#Preview {
    SettingsSheet()
}
