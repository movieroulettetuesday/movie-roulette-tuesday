import SwiftUI
import MRTCore
import MRTShared

/// Top tab bar (tvOS renders `TabView` as the mockup's Roulette · Episodes · Movies · Stats bar).
struct TVRootView: View {
    enum Tab: Hashable { case roulette, episodes, movies, stats }

    let roulette: RouletteViewModel
    @State private var tab: Tab = .roulette

    var body: some View {
        TabView(selection: $tab) {
            TVRouletteView(model: roulette)
                .tabItem { Text("Roulette") }
                .tag(Tab.roulette)
            TVPlaceholderView(title: "Episodes")
                .tabItem { Text("Episodes") }
                .tag(Tab.episodes)
            TVPlaceholderView(title: "Movies")
                .tabItem { Text("Movies") }
                .tag(Tab.movies)
            TVPlaceholderView(title: "Stats")
                .tabItem { Text("Stats") }
                .tag(Tab.stats)
        }
        .task {
            await roulette.load()
            await roulette.refreshRemoteCatalog()
        }
    }
}

/// Tabs that are not built yet (they need approved mockups first).
struct TVPlaceholderView: View {
    let title: String

    var body: some View {
        ZStack {
            TVBackground()
            VStack(spacing: 16) {
                Text(title)
                    .font(.system(size: 72, weight: .bold))
                    .foregroundStyle(TVPalette.white)
                Text("Coming soon to Apple TV")
                    .font(.system(size: 36))
                    .foregroundStyle(TVPalette.grey)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("tv.placeholder.\(title.lowercased())")
        }
    }
}

/// The mockups' dark backdrop: the Clean Pro dark gradient plus a faint teal glow top right.
struct TVBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: CleanProColors.backgroundDark.map { Color(hex: $0) },
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Brand.tealDark.opacity(0.35), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 900)
        }
        .ignoresSafeArea()
    }
}
