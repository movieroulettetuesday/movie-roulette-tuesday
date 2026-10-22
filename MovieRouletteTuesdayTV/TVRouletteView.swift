import SwiftUI
import MRTCore
import MRTShared

/// Roulette tab on Apple TV (mockups 01-wheel-home-dark and 02-result-dark).
///
/// Remote: Select on the focused pill spins (home) or spins again (result);
/// Play/Pause does the same from anywhere on this tab; Menu on the result goes
/// back to the wheel (on the idle home layout Menu keeps its system meaning).
/// During a spin (Matthew, Oct 21): Play/Pause stops it early (the result
/// still comes, as with the iOS hub Stop), swipes do nothing (focus stays on
/// the Spin pill), and Menu cancels the spin and goes back to the wheel home
/// with no result. The wheel is decorative and never focusable.
struct TVRouletteView: View {
    let model: RouletteViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    /// Rotates through all nine taglines, as on iOS: a random one at launch,
    /// a new one on every spin and after every result.
    @State private var tagline = RouletteTaglines.random()
    @FocusState private var focus: Control?

    enum Control: Hashable { case spin, spinAgain, moviePage }

    /// Mockup sizes (1920×1080 at 1×: mockup px = tvOS points).
    static let homeWheelDiameter: CGFloat = 760
    static let resultWheelDiameter: CGFloat = 520

    var body: some View {
        ZStack {
            TVBackground()
            content
            if let banner = model.rareBanner {
                Text(banner)
                    .font(.system(size: 96, weight: .heavy))
                    .foregroundStyle(Brand.ink)
                    .padding(.horizontal, 60).padding(.vertical, 24)
                    .background(Capsule().fill(Brand.jackpotGold))
                    .accessibilityIdentifier("tv.rareBanner")
                    .transition(.scale.combined(with: .opacity))
            }
        }
        // tvOS puts the initial focus on the tab bar; .defaultFocus alone does
        // not move it into the tab, so Spin takes focus once the wheel is loaded.
        .onAppear { if model.loadState == .loaded { focusPrimarySoon() } }
        .onChange(of: model.loadState) { _, state in
            if state == .loaded { focusPrimarySoon() }
        }
        .onPlayPauseCommand(perform: primaryAction)
        .onExitCommand(perform: exitAction)
        .onChange(of: model.reveal) { _, reveal in
            focus = reveal == nil ? Control.spin : Control.spinAgain
        }
        .onChange(of: focus) { _, newFocus in
            // Swipes do nothing during a spin: focus stays on the Spin pill.
            if isSpinLocked && newFocus != .spin { focus = .spin }
        }
        .onChange(of: isSpinLocked) { _, locked in
            if locked { focus = .spin }
        }
        .onChange(of: model.revealCount) { _, _ in
            tagline = RouletteTaglines.random(excluding: tagline)
        }
        .task(id: reduceMotion) { model.reduceMotion = reduceMotion }
        .onDisappear { model.stopFeedback() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.stopFeedback() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.loadState {
        case .loading:
            ProgressView().scaleEffect(2)
        case .failed(let message):
            VStack(spacing: 32) {
                Text(message)
                    .font(.system(size: 36))
                    .foregroundStyle(TVPalette.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 1100)
                Button("Try again") { Task { await model.load() } }
                    .buttonStyle(TVPillButtonStyle())
            }
        case .loaded:
            loadedLayout
        }
    }

    /// One wheel view for both layouts: it sits in the same slot of the HStack
    /// (the columns around it are conditional), so it keeps its identity and a
    /// spin started from the result (Spin Again) animates on the same wheel.
    private var loadedLayout: some View {
        let reveal = model.reveal
        return HStack(alignment: .center, spacing: 60) {
            if let reveal {
                resultColumn(reveal)
            }
            wheel(diameter: reveal == nil ? Self.homeWheelDiameter : Self.resultWheelDiameter)
                .frame(width: reveal == nil ? 840 : 600)
            if reveal == nil {
                homeColumn
            }
        }
        .padding(.horizontal, 90)
        .defaultFocus($focus, reveal == nil ? Control.spin : Control.spinAgain)
    }

    // MARK: Home (mockup 01)

    private var homeColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Movie Roulette")
                .font(.system(size: 88, weight: .bold))
                .foregroundStyle(TVPalette.white)
            Text(tagline)
                .font(.system(size: 40))
                .foregroundStyle(TVPalette.grey)
                .padding(.top, 8)
            Button(action: spinFromUser) {
                Text(model.isSpinning || model.isAwaitingForcedRespin ? "Spinning…" : "Spin")
            }
            .buttonStyle(TVPillButtonStyle())
            .focused($focus, equals: .spin)
            .accessibilityIdentifier("tv.spin")
            .accessibilityHint("Spins the wheel")
            .padding(.top, 70)
            lastLanded
                .padding(.top, 80)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }

    @ViewBuilder
    private var lastLanded: some View {
        if let last = model.history.results.last,
           let catalog = model.catalog,
           let movie = catalog.movie(withId: last.movieId) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Last landed on")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(TVPalette.grey)
                Text(movie.title)
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(TVPalette.white)
                    .lineLimit(2)
                HStack(spacing: 24) {
                    Text(String(movie.year))
                        .font(.system(size: 36))
                        .foregroundStyle(TVPalette.grey)
                    if let category = catalog.category(withId: last.categoryId) {
                        TVCategoryChip(category: category)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("tv.lastLanded")
        } else {
            // Keeps the column height stable before the first spin.
            Color.clear.frame(height: 170)
        }
    }

    // MARK: Result (mockup 02)

    private func resultColumn(_ reveal: RouletteViewModel.Reveal) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(reveal.isJackpot ? "INFAMOUS JACKPOT!" : "THE WHEEL HAS SPOKEN")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(reveal.isJackpot ? Brand.jackpotGold : TVPalette.teal)
            Text(reveal.movie.title)
                .font(.system(size: 128, weight: .heavy))
                .foregroundStyle(TVPalette.white)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .padding(.top, 12)
                .accessibilityIdentifier("tv.result.title")
            HStack(spacing: 28) {
                Text(String(reveal.movie.year))
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(TVPalette.grey)
                TVCategoryChip(category: reveal.category, text: reveal.category.displayName, size: 34)
            }
            .padding(.top, 20)
            whereToWatch(reveal.movie)
                .padding(.top, 40)
            HStack(spacing: 40) {
                Button(action: spinAgain) { Text("Spin Again") }
                    .buttonStyle(TVPillButtonStyle(width: 460, height: 132))
                    .focused($focus, equals: .spinAgain)
                    .accessibilityIdentifier("tv.spinAgain")
                // Movie Page on TV is phase 3 (needs its mockup); shown, not active yet.
                Button(action: {}) { Text("Movie Page") }
                    .buttonStyle(TVPillButtonStyle(primary: false, width: 420, height: 132))
                    .disabled(true)
                    .accessibilityIdentifier("tv.moviePage")
            }
            .padding(.top, 48)
            .focusSection()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func whereToWatch(_ movie: Movie) -> some View {
        let providers = Self.providers(for: movie)
        if !providers.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text("Where to watch")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(TVPalette.grey)
                HStack(spacing: 24) {
                    ForEach(providers, id: \.id) { provider in
                        Text(provider.name)
                            .font(.system(size: provider.name.count > 6 ? 24 : 30, weight: .heavy))
                            .foregroundStyle(TVPalette.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                            .multilineTextAlignment(.center)
                            .padding(8)
                            .frame(width: 120, height: 120)
                            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(TVPalette.pill))
                            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.2), lineWidth: 2))
                    }
                }
                .accessibilityElement(children: .combine)
                // Same streaming-data attribution as the iOS movie page (not in the mockup).
                if let footer = WhereToWatchDisplay(movie: movie).footer {
                    Text(footer)
                        .font(.system(size: 24))
                        .foregroundStyle(TVPalette.grey)
                }
            }
        }
    }

    /// Display-only tiles: subscription + free providers first, by priority, at most 5.
    static func providers(for movie: Movie) -> [StreamingInfo.Provider] {
        guard let streaming = movie.streaming else { return [] }
        var seen = Set<Int>()
        let ordered = (streaming.stream + streaming.free)
            .sorted { ($0.priority ?? .max) < ($1.priority ?? .max) }
        return Array(ordered.filter { seen.insert($0.id).inserted }.prefix(5))
    }

    // MARK: Wheel

    private func wheel(diameter: CGFloat) -> some View {
        let pointer = RouletteLayout.pointerSize(forDiameter: Double(diameter))
        return ZStack(alignment: .top) {
            TVSpinningWheel(model: model)
                .frame(width: diameter, height: diameter)
                .padding(.top, pointer.height * 0.5)
            WheelPointer()
                .fill(Color(hex: CleanProColors.pointerDark))
                .frame(width: pointer.width, height: pointer.height)
                .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Roulette wheel")
        .accessibilityValue(model.lastCategory.map { "Last landed on \($0.name)" } ?? "")
        .accessibilityIdentifier("tv.wheel")
    }

    // MARK: Actions

    /// A spin is in flight (or a forced re-spin is pending) on the home layout.
    private var isSpinLocked: Bool {
        model.reveal == nil && model.canCancel
    }

    /// Menu: during a spin, cancel it (back to the wheel home, no result); on
    /// the result, back to the wheel; otherwise nil so the system behavior
    /// (tab bar, then Home) is unchanged.
    private var exitAction: (() -> Void)? {
        if model.canCancel { return { cancelSpin() } }
        return model.reveal != nil ? { backToWheel() } : nil
    }

    /// Play/Pause: stop a spin early, spin from home, spin again from the result.
    private func primaryAction() {
        if model.isSpinning {
            model.stopEarly()
        } else if model.reveal != nil {
            spinAgain()
        } else {
            spinFromUser()
        }
    }

    /// Focus Spin (home) or Spin Again (result) on the next turn, once the
    /// loaded layout is in the hierarchy.
    private func focusPrimarySoon() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            focus = model.reveal == nil ? Control.spin : Control.spinAgain
        }
    }

    /// Menu during a spin: no result; the wheel home stays with Spin focused.
    private func cancelSpin() {
        model.cancelSpin()
        focus = .spin
    }

    private func spinFromUser() {
        guard model.canSpin else { return }
        tagline = RouletteTaglines.random(excluding: tagline)
        model.spin()
    }

    /// Same sequence as the iOS reveal sheet's Spin Again: request, clear the
    /// reveal, then the view model spins on the next main-actor turn.
    private func spinAgain() {
        guard model.reveal != nil else { return }
        model.spinAgain()
        model.revealDismissed()
    }

    /// Menu on the result: back to the wheel home (no spin).
    private func backToWheel() {
        model.reveal = nil
        model.revealDismissed()
    }
}

/// Its own view so `rotation` has its own observer (as on iOS).
private struct TVSpinningWheel: View {
    let model: RouletteViewModel

    var body: some View {
        WheelView(
            categories: model.catalog?.categories ?? [],
            geometry: model.geometry,
            rotation: model.rotation,
            stopOffset: model.stopOffset
        )
    }
}
