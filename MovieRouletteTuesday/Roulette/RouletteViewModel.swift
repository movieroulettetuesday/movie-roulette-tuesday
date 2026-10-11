import SwiftUI
import Observation
import QuartzCore

/// State and actions for the Roulette screen.
@MainActor
@Observable
final class RouletteViewModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    struct Reveal: Identifiable, Equatable {
        let id: UUID // the SpinResult id
        let movie: Movie
        let category: RouletteCategory
        /// Spin count for this movie on this device, including this spin.
        let spinCount: Int
        /// Rare "Infamous jackpot" outcome: special reveal styling.
        var isJackpot = false
    }

    /// The spin follows the recorded spin sound (`SpinMotion`): the wheel
    /// runs as long as the clip's ratchet and stops on its final thunk.
    /// Reduce Motion keeps that timeline but turns the wheel only 1–2 times.
    static var spinDuration: Double { SpinSoundTrack.spinDuration }
    static let fullTurns = 5...8
    static let reducedMotionFullTurns = 1...2
    /// Selection haptics closer together than this are skipped.
    static let hapticMinInterval = 0.045
    /// Pause on "Re-spin forced!" before the automatic re-spin.
    static let forcedRespinDelay = 1.6

    private(set) var loadState: LoadState = .loading
    private(set) var catalog: MovieCatalog?
    private(set) var geometry = WheelGeometry(segmentCount: 1)
    /// Total clockwise rotation in degrees. Accumulates across spins; never reset.
    private(set) var rotation: Double = 0
    private(set) var isSpinning = false
    private(set) var lastCategory: RouletteCategory?
    private(set) var notice: String?
    /// Bumped on every reveal; drives the haptic.
    private(set) var revealCount = 0
    /// Big overlay text for rare outcomes ("RE-SPIN FORCED!").
    private(set) var rareBanner: String?
    /// True between a forced re-spin message and the automatic re-spin.
    private(set) var isAwaitingForcedRespin = false
    var reveal: Reveal?

    let history: SpinHistoryStore

    /// Set by the view from the environment; shortens the spin.
    @ObservationIgnored var reduceMotion = false
    private let catalogSource: any MovieCatalogSource
    private let selector: MovieSelector
    @ObservationIgnored private var rng: AnyRandomNumberGenerator
    @ObservationIgnored private var spinAgainRequested = false
    private let feedback: SpinFeedback
    /// Fires the crossing haptics for the spin in flight (main actor).
    @ObservationIgnored private var hapticsTask: Task<Void, Never>?
    /// Identifies the spin in flight; a stale completion/watchdog is ignored.
    @ObservationIgnored private var spinToken = 0
    /// When the spin in flight should end (its animation's full duration).
    @ObservationIgnored private var spinEndsAt: ContinuousClock.Instant?
    /// Finishes the spin if SwiftUI never delivers the animation completion
    /// (e.g. the wheel was off-screen), so the wheel can't get stuck "spinning".
    @ObservationIgnored private var watchdogTask: Task<Void, Never>?
    /// The single pending automatic re-spin (never more than one).
    @ObservationIgnored private var forcedRespinTask: Task<Void, Never>?
    /// DEBUG stress runs: very short spins (unless `stressRealTiming`), no forced-respin pause.
    @ObservationIgnored private var stressMode = false
    /// DEBUG stress runs with the real, full-length clip-timed spins.
    @ObservationIgnored private var stressRealTiming = false
    private let settings: UserDefaults

    init(
        catalogSource: any MovieCatalogSource,
        history: SpinHistoryStore,
        selector: MovieSelector = MovieSelector(),
        rng: AnyRandomNumberGenerator = .system,
        settings: UserDefaults = .standard
    ) {
        self.catalogSource = catalogSource
        self.history = history
        self.selector = selector
        self.rng = rng
        self.settings = settings
        self.feedback = SpinFeedback()
    }

    var canSpin: Bool {
        catalog != nil && !isSpinning && reveal == nil && !isAwaitingForcedRespin
    }

    /// In-flight catalog load, shared so ContentView and RouletteView never load twice.
    @ObservationIgnored private var catalogLoadTask: Task<Void, Never>?

    /// Loads the catalog once. Safe to call from several views at the same time:
    /// later callers await the in-flight load. After a failure the next call retries.
    func load() async {
        guard catalog == nil else { return }
        if let catalogLoadTask {
            await catalogLoadTask.value
            return
        }
        let task = Task { await performLoad() }
        catalogLoadTask = task
        await task.value
        catalogLoadTask = nil
    }

    private func performLoad() async {
        loadState = .loading
        do {
            let loaded = try await catalogSource.loadCatalog()
            guard !loaded.categories.isEmpty else {
                loadState = .failed("The movie list has no categories.")
                return
            }
            let clean = loaded.deduplicated()
            catalog = clean
            geometry = WheelGeometry(categories: clean.categories)
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func spin() {
        startSpin(isForcedRespin: false)
    }

    private func startSpin(isForcedRespin: Bool) {
        if isForcedRespin {
            isAwaitingForcedRespin = false
        }
        guard canSpin else { return }
        spinToken &+= 1
        let token = spinToken
        let start = rotation
        let shortStress = stressMode && !stressRealTiming
        let target = geometry.randomTargetRotation(
            from: start,
            fullTurns: (reduceMotion || shortStress) ? Self.reducedMotionFullTurns : Self.fullTurns,
            using: &rng
        )
        let duration: Double
        let animation: Animation
        let crossings: [Double]
        if shortStress {
            duration = Self.stressSpinDuration
            animation = .easeOut(duration: duration)
            crossings = SpinTicks.tickTimes(from: start, to: target, geometry: geometry,
                                            curve: .easeOut, duration: duration, minInterval: 0)
        } else {
            // Timing (not outcome) is locked to the recorded clip.
            let motion = SpinMotion.plan(from: start, to: target, geometry: geometry)
            duration = motion.duration
            animation = Animation(SpinMotionAnimation(motion: motion, id: token))
            crossings = motion.crossingTimes
        }
        startFeedback(crossings: crossings)
        spinEndsAt = ContinuousClock.now.advanced(by: .seconds(duration))
        // The animated `rotation` change goes first, before any other observed
        // state changes in this update (see SpinningWheel in RouletteView).
        // `.removed` fires once the animation has fully finished (iOS 17).
        withAnimation(animation, completionCriteria: .removed) {
            rotation = target
        } completion: { [weak self] in
            self?.spinAnimationEnded(token: token, wasForcedRespin: isForcedRespin)
        }
        isSpinning = true
        notice = isForcedRespin ? "Re-spin forced! Here we go again…" : nil
        watchdogTask?.cancel()
        watchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration + RouletteViewModel.watchdogGrace))
            guard !Task.isCancelled else { return }
            self?.finishSpin(token: token, wasForcedRespin: isForcedRespin)
        }
    }

    static let stressSpinDuration = 0.25
    static let watchdogGrace = 1.5

    /// Stops the spin sound (fade) and pending haptics: view disappeared or
    /// app went to the background. The spin result itself is unaffected.
    func stopFeedback() {
        hapticsTask?.cancel()
        hapticsTask = nil
        feedback.stopClip(fade: true)
    }

    /// Starts the recorded spin sound (whole clip, once; audio queue, never
    /// main) and schedules a selection haptic at each boundary crossing (main
    /// actor), both measured from this instant, the animation's start.
    private func startFeedback(crossings: [Double]) {
        hapticsTask?.cancel()
        hapticsTask = nil
        let sound = AppSettings.bool(AppSettings.tickSound, store: settings)
        let haptics = AppSettings.bool(AppSettings.haptics, store: settings)
        feedback.stopClip(fade: false)  // a previous clip never overlaps a new spin
        guard sound || haptics else { return }
        feedback.prepare(sound: sound, haptics: haptics)
        if sound { feedback.startClip(startedAt: CACurrentMediaTime()) }
        guard haptics else { return }
        let times = SpinTicks.thinned(crossings, minInterval: Self.hapticMinInterval)
        guard !times.isEmpty else { return }
        let feedback = self.feedback
        hapticsTask = Task { @MainActor in
            let clock = ContinuousClock()
            let began = clock.now
            for time in times {
                try? await Task.sleep(until: began.advanced(by: .seconds(time)), clock: clock)
                if Task.isCancelled { return }
                feedback.crossing()
            }
        }
    }

    /// The reveal must never come before the wheel has stopped: if SwiftUI
    /// reports the animation done early (e.g. its completion got tied to
    /// another transaction), finish at the planned end instead.
    private func spinAnimationEnded(token: Int, wasForcedRespin: Bool) {
        guard isSpinning, token == spinToken else { return }
        if let end = spinEndsAt, end - ContinuousClock.now > .milliseconds(50) {
            Task { @MainActor [weak self] in
                try? await Task.sleep(until: end, clock: ContinuousClock())
                self?.finishSpin(token: token, wasForcedRespin: wasForcedRespin)
            }
            return
        }
        finishSpin(token: token, wasForcedRespin: wasForcedRespin)
    }

    /// Called from the reveal sheet: dismiss, then spin once the sheet is gone.
    func spinAgain() {
        spinAgainRequested = true
        reveal = nil
    }

    func revealDismissed() {
        guard spinAgainRequested else { return }
        spinAgainRequested = false
        // Next main-actor turn: outside the sheet-dismissal transaction, so the
        // spin's animation (and its completion) is entirely its own.
        Task { @MainActor [weak self] in self?.spin() }
    }

    private func finishSpin(token: Int, wasForcedRespin: Bool) {
        // Exactly once per spin: whichever of completion/watchdog comes first.
        guard isSpinning, token == spinToken else { return }
        defer { isSpinning = false }
        watchdogTask?.cancel()
        watchdogTask = nil
        hapticsTask?.cancel()
        hapticsTask = nil
        // Normal spins end on the clip's last thunk (let its decay ring out);
        // short stress spins end early, so fade the clip.
        if stressMode && !stressRealTiming { feedback.stopClip(fade: true) }
        rareBanner = nil
        guard let catalog else { return }

        // The winner comes purely from the final angle, using the same geometry the wheel is drawn with.
        let index = geometry.segmentIndex(forRotation: rotation)
        guard catalog.categories.indices.contains(index) else { return }
        let landed = catalog.categories[index]
        lastCategory = landed

        // Rare outcomes (~1% each; toggle in Settings). Re-spins never chain.
        let policy = RareOutcomePolicy(isEnabled: AppSettings.bool(AppSettings.rareOutcomes, store: settings))
        let outcome = RareOutcomeRoller.roll(
            policy: policy,
            infamousAvailable: !RareOutcomeRoller.infamousMovies(in: catalog).isEmpty,
            allowRespin: !wasForcedRespin,
            using: &rng
        )

        if outcome == .forcedRespin {
            notice = "Re-spin forced! The wheel demands a do-over."
            rareBanner = "RE-SPIN FORCED!"
            isAwaitingForcedRespin = true
            forcedRespinTask?.cancel()
            let delay = stressMode ? 0.2 : RouletteViewModel.forcedRespinDelay
            forcedRespinTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }
                self.forcedRespinTask = nil
                self.rareBanner = nil
                self.startSpin(isForcedRespin: true)
            }
            return
        }

        var category = landed
        var isJackpot = false
        let movie: Movie
        if outcome == .infamousJackpot,
           let pick = RareOutcomeRoller.jackpotPick(in: catalog, landed: landed, using: &rng) {
            movie = pick.movie
            category = pick.category
            isJackpot = true
        } else if let picked = selector.selectMovie(
            from: landed, in: catalog, history: history.results, using: &rng
        ) {
            movie = picked
        } else {
            notice = "No movies in \(landed.name) yet. Spin again!"
            return
        }
        if isJackpot { notice = "INFAMOUS JACKPOT!" }

        let result = SpinResult(movieId: movie.id, categoryId: category.id)
        history.record(result)
        WidgetBridge.publishSpin(movie: movie, category: category, at: result.timestamp)
        reveal = Reveal(
            id: result.id,
            movie: movie,
            category: category,
            spinCount: history.stats.spinCount(forMovie: movie.id),
            isJackpot: isJackpot
        )
        revealCount += 1
    }
}

#if DEBUG
extension RouletteViewModel {
    /// `-MRTStressRealTiming`: stress with full-length, clip-timed spins.
    static var stressRealTimingArgument: Bool {
        ProcessInfo.processInfo.arguments.contains("-MRTStressRealTiming")
    }

    /// `-MRTStressSpins N` launch argument (DEBUG builds only).
    static var stressSpinArgument: Int? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-MRTStressSpins"), args.indices.contains(i + 1),
              let n = Int(args[i + 1]), n > 0 else { return nil }
        return min(n, 10_000)
    }

    /// Unbuffered (stderr) so progress is visible even when output goes to a file.
    static func stressLog(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    /// Performs `count` rapid spins with a shortened animation, presenting and
    /// auto-dismissing each reveal sheet. Progress goes to stdout as
    /// `MRT-STRESS ...` lines. Nothing else about spinning changes.
    func runStressSpins(_ count: Int) async {
        stressMode = true
        stressRealTiming = Self.stressRealTimingArgument
        defer { stressMode = false; stressRealTiming = false }
        Self.stressLog("MRT-STRESS start \(count) realTiming=\(stressRealTiming)")
        let clock = ContinuousClock()
        var completed = 0
        var lastProgress = clock.now
        while completed < count, !Task.isCancelled {
            if reveal != nil {
                try? await Task.sleep(for: .milliseconds(400))  // let the sheet render its share card
                reveal = nil
                try? await Task.sleep(for: .milliseconds(600))  // let the dismissal finish
                lastProgress = clock.now
                continue
            }
            if canSpin {
                spin()
                completed += 1
                lastProgress = clock.now
                Self.stressLog("MRT-STRESS spin \(completed)/\(count)")
            } else if clock.now - lastProgress > .seconds(15) {
                Self.stressLog("MRT-STRESS STUCK isSpinning=\(isSpinning) awaitingRespin=\(isAwaitingForcedRespin)")
                break
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        // Let the last spin finish and close its reveal.
        for _ in 0..<120 where isSpinning || isAwaitingForcedRespin || reveal != nil {
            if reveal != nil { try? await Task.sleep(for: .milliseconds(400)); reveal = nil }
            try? await Task.sleep(for: .milliseconds(100))
        }
        Self.stressLog("MRT-STRESS done \(completed) spins, totalSpins=\(history.totalSpins), detailed=\(history.results.count)")
    }
}
#endif

extension RouletteViewModel {
    /// Bundled data + in-memory history, for SwiftUI previews.
    static func preview() -> RouletteViewModel {
        RouletteViewModel(
            catalogSource: BundleCatalogSource(),
            history: SpinHistoryStore(fileStore: nil)
        )
    }
}
