import SwiftUI

struct RouletteView: View {
    @Bindable var model: RouletteViewModel
    var episodesByGUID: [String: PodcastEpisode] = [:]
    var showArtworkURL: URL? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Cold-launch opening (nil in previews): the wheel fades/scales in under it.
    @Environment(SplashState.self) private var splash: SplashState?
    #if DEBUG
    @State private var stressStarted = false
    @State private var debugHistoryOpened = false
    @State private var debugAutoSpun = false
    #endif
    @State private var subtitle = RouletteTaglines.random()
    /// Measured height of the "Tap to spin" hint under the wheel (reserved in the slot).
    @State private var hintHeight: CGFloat = 18
    #if DEBUG
    @State private var debugLoggedHub: CGPoint?
    #endif
    @State private var showingRules = false
    @State private var showingHistory = false
    @State private var showingSettings = false
    @AppStorage(AppSettings.haptics) private var hapticsEnabled = true
    @Environment(PersonalRatingsStore.self) private var personal
    @Environment(CommunityService.self) private var community

    var body: some View {
        NavigationStack {
            Group {
                switch model.loadState {
                case .loading:
                    ProgressView("Loading movies…")
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Couldn't Load Movies", systemImage: "film.stack")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try Again") { Task { await model.load() } }
                    }
                case .loaded:
                    loadedContent
                }
            }
            // Magic Tap (two-finger double tap) spins from anywhere on the screen.
            .accessibilityAction(.magicTap) { spinFromUser() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { CleanProBackground() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingHistory = true } label: {
                        Label("Spin History", systemImage: "clock.arrow.circlepath")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showingRules = true } label: {
                        Label("Rules", systemImage: "info.circle")
                    }
                    Button { showingSettings = true } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsSheet(categories: model.catalog?.categories ?? [], knownEpisodes: Array(episodesByGUID.values))
                    .appAppearance()
                    .adaptiveSheetSizing()
            }
            .sheet(isPresented: $showingRules) {
                RulesSheet(presenterIsRegularWidth: horizontalSizeClass == .regular)
                    .appAppearance()
                    .adaptiveSheetSizing()
            }
            .sheet(isPresented: $showingHistory) {
                SpinHistoryView(
                    history: model.history,
                    catalog: model.catalog,
                    episodesByGUID: episodesByGUID,
                    showArtworkURL: showArtworkURL
                )
                    // Re-inject for the episode/movie pages pushed inside the sheet.
                    .environment(personal)
                    .environment(community)
                    .environment(model.history)
                    .appAppearance()
                    .adaptiveSheetSizing()
            }
            .sheet(item: $model.reveal, onDismiss: { model.revealDismissed() }) { reveal in
                RevealSheet(
                    reveal: reveal,
                    catalog: model.catalog,
                    episodesByGUID: episodesByGUID,
                    showArtworkURL: showArtworkURL,
                    onSpinAgain: { model.spinAgain() },
                    presenterIsRegularWidth: horizontalSizeClass == .regular
                )
                // Re-inject for the movie page pushed inside the sheet.
                .environment(personal)
                .environment(community)
                .environment(model.history)
                .appAppearance()
                .adaptiveSheetSizing()
            }
            .sensoryFeedback(.impact(weight: .light), trigger: model.revealCount) { _, _ in hapticsEnabled }
            .task {
                await model.load()
                #if DEBUG
                if !debugHistoryOpened {
                    debugHistoryOpened = true
                    if DebugLaunch.showsHistory { showingHistory = true }
                    else if DebugLaunch.showsRules { showingRules = true }
                }
                // UI tests: start a spin the way VoiceOver activation / Magic Tap
                // do (an accessibility action, no touch gesture in flight).
                if !debugAutoSpun, DebugLaunch.value(for: "-MRTAutoSpin") != nil {
                    debugAutoSpun = true
                    try? await Task.sleep(for: .seconds(3))
                    spinFromUser()
                }
                if !stressStarted, let count = RouletteViewModel.stressSpinArgument {
                    stressStarted = true
                    await model.runStressSpins(count)
                }
                #endif
            }
            .task(id: reduceMotion) { model.reduceMotion = reduceMotion }
            // The spin sound (faded) and scheduled haptics never outlive the screen.
            .onDisappear { model.stopFeedback() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { model.stopFeedback() }
            }
            .onChange(of: model.revealCount) { _, _ in
                subtitle = RouletteTaglines.random(excluding: subtitle)
            }
        }
    }

    /// Layout comes from the available size + size class (never the device
    /// type), so narrow iPad windows get the iPhone layout. There is no SPIN
    /// pill: the hub is the spin button and "Tap to spin" sits under the wheel,
    /// so the wheel fills the slot below the header (see
    /// `RouletteLayout.wheelDiameter`): it grows on big screens and shrinks on
    /// small phones or at large Dynamic Type sizes instead of crowding the text.
    /// Its diameter depends only on the slot size and the hint's (fixed per
    /// Dynamic Type size) height, so labels never resize mid-spin.
    private var loadedContent: some View {
        GeometryReader { proxy in
            let isRegular = horizontalSizeClass == .regular
            let layout = RouletteLayout.make(
                width: proxy.size.width,
                height: proxy.size.height,
                isRegularWidth: isRegular
            )
            Group {
                switch layout.arrangement {
                case .stacked:
                    VStack(spacing: 0) {
                        header
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                            .padding(.top, 4)
                        wheelSlot(arrangement: .stacked, isRegularWidth: isRegular)
                            .padding(.bottom, 8)
                    }
                case .sideBySide:
                    HStack(spacing: 40) {
                        wheelSlot(arrangement: .sideBySide, isRegularWidth: isRegular)
                        header
                            .frame(width: RouletteLayout.sideBySideControlsWidth(forWidth: proxy.size.width),
                                   alignment: .leading)
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 16)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    /// Flexible slot; the wheel and the hint under it are centered in it, the
    /// wheel at the largest diameter that fits.
    private func wheelSlot(arrangement: RouletteLayout.Arrangement, isRegularWidth: Bool) -> some View {
        GeometryReader { slot in
            let diameter = CGFloat(RouletteLayout.wheelDiameter(
                slotWidth: slot.size.width,
                slotHeight: slot.size.height,
                arrangement: arrangement,
                isRegularWidth: isRegularWidth,
                hintHeight: Double(hintHeight)
            ))
            // Centered in the slot: equal room above the pointer and below the
            // hint (the wheel's soft shadow uses the gap above the hint).
            VStack(spacing: CGFloat(RouletteLayout.hintSpacing)) {
                wheel(diameter: diameter)
                statusLine
                    .padding(.horizontal, 16)
                    .background {
                        GeometryReader { g in
                            Color.clear
                                .onAppear { hintHeight = g.size.height }
                                .onChange(of: g.size.height) { _, h in hintHeight = h }
                        }
                    }
            }
                .frame(width: slot.size.width, height: slot.size.height)
                #if DEBUG
                .task(id: Int(diameter)) {
                    FileHandle.standardError.write(Data("MRT-WHEEL diameter=\(Int(diameter)) slot=\(Int(slot.size.width))x\(Int(slot.size.height))\n".utf8))
                }
                #endif
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Movie Roulette")
                .font(.largeTitle.bold())
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// The wheel (one combined "Roulette wheel" element; tapping it spins) with
    /// the hub spin button over its centre as a separate "Spin" button.
    private func wheel(diameter: CGFloat) -> some View {
        let pointer = RouletteLayout.pointerSize(forDiameter: Double(diameter))
        let hubSize = diameter * 0.23
        return ZStack(alignment: .top) {
            wheelArt(diameter: diameter, pointer: pointer)
            // Same square as the wheel face, so the button sits exactly on the hub.
            // Only the button itself takes touches; the rest of the face falls through.
            HubSpinButton(hubSize: hubSize, enabled: model.canSpin) { spinFromUser() }
                .frame(width: diameter, height: diameter)
                .background {
                    GeometryReader { g in
                        Color.clear
                            .onAppear { reportHub(g.frame(in: .global), size: hubSize) }
                            .onChange(of: g.frame(in: .global)) { _, f in reportHub(f, size: hubSize) }
                    }
                    .allowsHitTesting(false)
                }
                .modifier(SplashWheelEffect(state: splash))
                .padding(.top, pointer.height * 0.5)
        }
        // Above the hub button, so the rare-outcome banner is never under its ring.
        .overlay {
            if let banner = model.rareBanner {
                Text(banner)
                    // Scales with the wheel (28pt on a typical iPhone wheel).
                    .font(.system(size: min(max(diameter * 0.1, 22), 44), weight: .black, design: .rounded))
                    .foregroundStyle(Brand.ink)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color(hex: CleanProColors.peach), in: Capsule())
                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
                    .transition(.scale.combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.spring(duration: 0.35), value: model.rareBanner)
        .frame(width: diameter, height: CGFloat(RouletteLayout.wheelFrameHeight(forDiameter: Double(diameter))))
    }

    private func wheelArt(diameter: CGFloat, pointer: (width: Double, height: Double)) -> some View {
        ZStack(alignment: .top) {
            // Only the face rotates inside WheelView (render-only transform, no
            // relayout); rim, hub, shadow and pointer stay static.
            // Its own view, so `rotation` has its own observer (see SpinningWheel).
            SpinningWheel(model: model)
                .contentShape(Circle())
                .onTapGesture { spinFromUser() }
                // Cold-launch opening: fades/scales in with a small settle (identity afterwards).
                .modifier(SplashWheelEffect(state: splash))
                .padding(.top, pointer.height * 0.5)

            WheelPointer()
                .fill(Color(hex: colorScheme == .dark ? CleanProColors.pointerDark : CleanProColors.pointerLight))
                .frame(width: pointer.width, height: pointer.height)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.18), radius: 3, y: 2)
                .allowsHitTesting(false)
        }
        .frame(width: diameter, height: CGFloat(RouletteLayout.wheelFrameHeight(forDiameter: Double(diameter))))
        .allowsHitTesting(model.canSpin)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Roulette wheel")
        .accessibilityValue(model.lastCategory.map { "Last landed on \($0.name)" } ?? "")
        .accessibilityHint("Double tap to spin")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { spinFromUser() }
    }

    private func spinFromUser() {
        guard model.canSpin else { return }
        subtitle = RouletteTaglines.random(excluding: subtitle)
        model.spin()
    }

    private func reportHub(_ frame: CGRect, size: CGFloat) {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        splash?.reportHub(center: center, size: size)
        #if DEBUG
        let rounded = CGPoint(x: center.x.rounded(), y: center.y.rounded())
        if rounded != debugLoggedHub {
            debugLoggedHub = rounded
            FileHandle.standardError.write(Data("MRT-HUB center=\(Int(rounded.x)),\(Int(rounded.y)) size=\(Int(size.rounded()))\n".utf8))
        }
        #endif
    }

    private var statusLine: some View {
        Group {
            if let notice = model.notice {
                Text(notice)
            } else if model.isSpinning {
                Text("No take-backsies…")
            } else if let category = model.lastCategory {
                Text("Last landed on \(category.name)")
            } else {
                Text("Tap to spin")
            }
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        // Fixed height per Dynamic Type size (one line, two at accessibility
        // sizes), so a longer status never resizes the wheel mid-spin.
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1, reservesSpace: true)
        .minimumScaleFactor(0.8)
        .frame(minHeight: 18)
    }
}

#Preview {
    RouletteView(model: .preview())
        .environment(PersonalRatingsStore(fileStore: nil))
        .environment(SpinHistoryStore(fileStore: nil))
        .environment(CommunityService.preview())
}


/// The rotating wheel, observing only what it draws (`catalog`, `geometry`,
/// `rotation`). Keep it this way: with `@Observable`, a view's change tracking
/// fires once per render, so if the parent also read `rotation` and some other
/// spin state (`isSpinning`, `notice`, …) changed first in the same update, the
/// animated `rotation` change was folded into that non-animated update and the
/// wheel jumped to its target instead of spinning. That only stayed hidden for
/// Button taps (whose updates SwiftUI batches); wheel taps, VoiceOver
/// activation, Magic Tap and Spin Again all froze.
private struct SpinningWheel: View {
    let model: RouletteViewModel

    var body: some View {
        WheelView(
            categories: model.catalog?.categories ?? [],
            geometry: model.geometry,
            rotation: model.rotation
        )
    }
}
