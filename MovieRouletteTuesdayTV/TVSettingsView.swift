import SwiftUI
import MRTCore
import MRTShared

/// Settings, pushed from Stats (mockup 10). No fifth tab.
/// Spin sound, Apple Podcasts, Spotify, and Suggest. Appearance follows the system.
struct TVSettingsView: View {
    var onSuggest: () -> Void
    var onBack: () -> Void

    @AppStorage(AppSettings.tickSound) private var tickSound = true
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL
    @FocusState private var soundFocused: Bool
    @State private var openNote: String?

    private var theme: TVTheme { TVTheme(scheme: scheme) }
    private var show: ShowInfo { .mrt }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TVBackHeader(title: "Stats", action: onBack)
            HStack(alignment: .top, spacing: 72) {
                brand
                    .frame(width: 420)
                form
            }
            Spacer(minLength: 0)
            Text("MENU Back to Stats")
                .font(.system(size: 26))
                .foregroundStyle(theme.secondary)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 80)
        .padding(.top, 28)
        .padding(.bottom, 20)
        .accessibilityIdentifier("tv.screen.settings")
        .defaultFocus($soundFocused, true)
        .onExitCommand(perform: onBack)
    }

    private var brand: some View {
        VStack(spacing: 22) {
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 360, height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
                .accessibilityHidden(true)
            Text("Movie Roulette Tuesday")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(theme.text)
                .multilineTextAlignment(.center)
            Text("Version \(marketingVersion)")
                .font(.system(size: 26))
                .foregroundStyle(theme.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    private var marketingVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Settings")
                .font(.system(size: 76, weight: .bold))
                .foregroundStyle(theme.text)
            sectionLabel("SPIN")
            Button { tickSound.toggle() } label: {
                HStack {
                    Text("Spin sound")
                        .font(.system(size: 36, weight: .semibold))
                    Spacer()
                    TVSwitch(on: tickSound)
                }
            }
            .buttonStyle(TVRowButtonStyle())
            .focused($soundFocused)
            .accessibilityIdentifier("tv.settings.spinSound")
            .accessibilityValue(tickSound ? "On" : "Off")
            .accessibilityAddTraits(.isToggle)
            Text("A tick plays as each slice passes the pointer.")
                .font(.system(size: 26))
                .foregroundStyle(theme.secondary)
            sectionLabel("FOLLOW THE SHOW")
            linkRow("Apple Podcasts", symbol: "apple.logo", tint: Color(hex: "#9B4DE0"), url: PodcastLinks.appleShow(show: show), id: "tv.settings.apple")
            linkRow("Spotify", symbol: "waveform", tint: Color(hex: "#1DB954"), url: PodcastLinks.spotifyShow(show: show), id: "tv.settings.spotify")
            sectionLabel("SUGGEST")
            Button(action: onSuggest) {
                HStack {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 28, weight: .bold))
                    Text("Suggest a movie")
                        .font(.system(size: 34, weight: .semibold))
                    Spacer()
                    Text("QR code")
                        .font(.system(size: 28, weight: .medium))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 22, weight: .bold))
                }
            }
            .buttonStyle(TVRowButtonStyle())
            .accessibilityIdentifier("tv.settings.suggest")
            if let openNote {
                Text(openNote)
                    .font(.system(size: 26))
                    .foregroundStyle(.orange)
            }
            Text("Appearance follows your Apple TV’s Light/Dark setting.")
                .font(.system(size: 26))
                .foregroundStyle(theme.secondary)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { TVFocus.soon { soundFocused = true } }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(theme.secondary)
            .padding(.top, 8)
    }

    @ViewBuilder
    private func linkRow(_ title: String, symbol: String, tint: Color, url: URL?, id: String) -> some View {
        Button {
            guard let url else { openNote = "\(title) isn’t available."; return }
            openNote = nil
            TVOpen.first(of: [url], with: openURL, failure: "Couldn’t open \(title).") { openNote = $0 }
        } label: {
            HStack(spacing: 16) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint))
                Text(title)
                    .font(.system(size: 34, weight: .semibold))
                Spacer()
                Text("Open")
                    .font(.system(size: 28, weight: .medium))
                Image(systemName: "chevron.right")
                    .font(.system(size: 22, weight: .bold))
            }
        }
        .buttonStyle(TVRowButtonStyle())
        .accessibilityIdentifier(id)
        .accessibilityHint("Opens outside the app")
    }
}

private struct TVSwitch: View {
    var on: Bool
    var body: some View {
        Capsule()
            .fill(on ? Brand.teal : Color(hex: "#5C6B6E"))
            .frame(width: 84, height: 48)
            .overlay(alignment: on ? .trailing : .leading) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 38, height: 38)
                    .padding(5)
            }
            .accessibilityHidden(true)
    }
}
