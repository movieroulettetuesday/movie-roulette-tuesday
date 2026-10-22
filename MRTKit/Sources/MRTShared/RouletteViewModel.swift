import SwiftUI
import Observation
import QuartzCore
import MRTCore

/// Platform hooks the view model calls after its own state changes. The iOS
/// app passes `.widgetBridge` (WidgetKit); tvOS has no widget and uses `.none`.
public struct RouletteSideEffects: Sendable {
    /// A refreshed movie list was offered (applied now or when idle).
    public var catalogUpdated: @MainActor @Sendable () -> Void
    /// A spin landed and was recorded in the history.
    public var spinRecorded: @MainActor @Sendable (_ movie: Movie, _ category: RouletteCategory, _ date: Date) -> Void

    public init(
        catalogUpdated: @escaping @MainActor @Sendable () -> Void = {},
        spinRecorded: @escaping @MainActor @Sendable (_ movie: Movie, _ category: RouletteCategory, _ date: Date) -> Void = { _, _, _ in }
    ) {
        self.catalogUpdated = catalogUpdated
        self.spinRecorded = spinRecorded
    }

    /// No side effects (previews, tests, tvOS).
    public static var none: RouletteSideEffects { RouletteSideEffects() }
}

/// State and actions for the Roulette screen.
@MainActor
@Observable
public final class RouletteViewModel {
    public enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    public struct Reveal: Identifiable, Equatable {
        public let id: UUID // the SpinResult id
        public let movie: Movie
        public let category: RouletteCategory
        /// Spin count for this movie on this device, including this spin.
        public let spinCount: Int
        /// Rare "Infamous jackpot" outcome: special reveal styling.
        public var isJackpot = false

        public init(id: UUID, movie: Movie, category: RouletteCategory, spinCount: Int, isJackpot: Bool = false) {
            self.id = id
            self.movie = movie
            self.category = category
            self.spinCount = spinCount
            self.isJackpot = isJackpot
        }
    }

    /// The spin follows the recorded spin sound (`SpinMotion`): the wheel
    /// runs as long as the clip's ratchet and stops on its final thunk.
    /// Reduce Motion keeps that timeline but turns the wheel only 1–2 times.
    public static var spinDuration: Double { SpinSoundTrack.spinDuration }
    public static let fullTurns = 5...8
    public static let reducedMotionFullTurns = 1...2
    /// Selection haptics closer together than this are skipped.
    public static let hapticMinInterval = 0.045
    /// Pause on "Re-spin forced!" before the automatic re-spin.
    public static let forcedRespinDelay = 1.6

    public private(set) var loadState: LoadState = .loading
    public private(set) var catalog: MovieCatalog?
    public private(set) var geometry = WheelGeometry(segmentCount: 1)
    /// Total clockwise rotation in degrees. Accumulates across spins; never reset.
    public private(set) var rotation: Double = 0
    public private(set) var isSpinning = false
    /// Static extra rotation drawn while a stopped spin decelerates (SpinStopPlan.offset); 0 otherwise.
    public private(set) var stopOffset: Double = 0
    /// True from a stop tap until the wheel has settled.
    public private(set) var isStopping = false
    /// The spin in flight can be stopped early (clip-timed spins only).
    public private(set) var spinIsStoppable = false
    public private(set) var lastCategory: RouletteCategory?
    public private(set) var notice: String?
    /// Bumped on every reveal; drives the haptic.
    public private(set) var revealCount = 0
    /// Big overlay text for rare outcomes ("RE-SPIN FORCED!").
    public private(set) var rareBanner: String?
    /// True between a forced re-spin message and the automatic re-spin.
    public private(set) var isAwaitingForcedRespin = false
    public var reveal: Reveal?

    public let history: SpinHistoryStore

    /// Set by the view from the environment; shortens the spin.
    @ObservationIgnored public var reduceMotion = false
    private let catalogSource: any MovieCatalogSource
    /// Background GitHub refresh; nil = bundled/cached list only.
    private let catalogRefresher: CatalogRefresher?
    /// A refreshed list that arrived mid-spin or while a reveal is up; applied when idle.
    @ObservationIgnored private var pendingCatalog: MovieCatalog?
    @ObservationIgnored private var catalogRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var lastCatalogRefresh: ContinuousClock.Instant?
    /// Launch + pull-to-refresh can fire together; refreshes closer than this are skipped.
    public static let catalogRefreshMinInterval: Duration = .seconds(15)
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
    /// The clip-timed spin in flight (for tap-to-stop).
    @ObservationIgnored private var activeSpin: (start: Double, target: Double, motion: SpinMotion, began: CFTimeInterval, control: SpinStopControl, wasForcedRespin: Bool)?
    /// Where a stopped spin lands; applied to `rotation` when it settles.
    @ObservationIgnored private var pendingFinalRotation: Double?
    /// Finishes the spin if SwiftUI never delivers the animation completion
    /// (e.g. the wheel was off-screen), so the wheel can't get stuck "spinning".
    @ObservationIgnored private var watchdogTask: Task<Void, Never>?
    /// Set by `cancelSpin()`: the spin in flight ends with no result.
    @ObservationIgnored private var cancelRequested = false
    /// The single pending automatic re-spin (never more than one).
    @ObservationIgnored private var forcedRespinTask: Task<Void, Never>?
    /// DEBUG stress runs: very short spins (unless `stressRealTiming`), no forced-respin pause.
    @ObservationIgnored private var stressMode = false
    /// DEBUG stress runs with the real, full-length clip-timed spins.
    @ObservationIgnored private var stressRealTiming = false
    private let settings: UserDefaults
    private let sideEffects: RouletteSideEffects

    public init(
        catalogSource: any MovieCatalogSource,
        catalogRefresher: CatalogRefresher? = nil,
        history: SpinHistoryStore,
        selector: MovieSelector = MovieSelector(),
        rng: AnyRandomNumberGenerator = .system,
        settings: UserDefaults = .standard,
        sideEffects: RouletteSideEffects = .none
    ) {
        self.catalogSource = catalogSource
        self.catalogRefresher = catalogRefresher
        self.history = history
        self.selector = selector
        self.rng = rng
        self.settings = settings
        self.sideEffects = sideEffects
        self.feedback = SpinFeedback()
    }

    /// Tap-to-stop is available: spinning, not already stopping, not a stress run.
    public var canStop: Bool { isSpinning && spinIsStoppable && !isStopping }

    /// A spin (or a pending forced re-spin) can be called off: tvOS Menu.
    public var canCancel: Bool { isSpinning || isAwaitingForcedRespin }

    public var canSpin: Bool {
        catalog != nil && !isSpinning && reveal == nil && !isAwaitingForcedRespin
    }

    /// In-flight catalog load, shared so ContentView and RouletteView never load twice.
    @ObservationIgnored private var catalogLoadTask: Task<Void, Never>?

    /// Loads the catalog once. Safe to call from several views at the same time:
    /// later callers await the in-flight load. After a failure the next call retries.
    public func load() async {
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
                loadState = .failed("The movie list couldn’t be loaded. Check your connection and try again.")
                return
            }
            // A remote refresh may have landed first; it is newer, keep it.
            guard catalog == nil else { loadState = .loaded; return }
            apply(loaded.deduplicated())
        } catch {
            loadState = .failed("The movie list couldn’t be loaded. Check your connection and try again.")
        }
    }

    public func spin() {
        startSpin(isForcedRespin: false)
    }

    // MARK: Remote catalog

    /// Fetches the latest movie list (short timeout, off the main actor) and swaps
    /// it in when it validates. Never blocks the UI; failures keep the current list.
    /// Swaps are deferred while a spin or reveal is in progress.
    public func refreshRemoteCatalog() async {
        guard let catalogRefresher else { return }
        if let catalogRefreshTask { await catalogRefreshTask.value; return }
        let now = ContinuousClock.now
        if let last = lastCatalogRefresh, now - last < Self.catalogRefreshMinInterval { return }
        lastCatalogRefresh = now
        let task = Task { [weak self] in
            guard let fresh = try? await catalogRefresher.refresh() else { return }
            self?.offerRefreshedCatalog(fresh)
        }
        catalogRefreshTask = task
        await task.value
        catalogRefreshTask = nil
    }

    /// Movie ids are the stable key for spin history, ratings and votes, so a new
    /// list simply replaces the old one; ids that disappear keep their history.
    public func offerRefreshedCatalog(_ fresh: MovieCatalog) {
        let clean = fresh.deduplicated()
        guard clean != catalog else { return }
        if catalog == nil || isIdleForCatalogSwap {
            apply(clean)
        } else {
            pendingCatalog = clean
        }
        sideEffects.catalogUpdated()
    }

    private var isIdleForCatalogSwap: Bool {
        !isSpinning && reveal == nil && !isAwaitingForcedRespin
    }

    private func applyPendingCatalogIfIdle() {
        guard let pending = pendingCatalog, isIdleForCatalogSwap else { return }
        pendingCatalog = nil
        if pending != catalog { apply(pending) }
    }

    private func apply(_ clean: MovieCatalog) {
        catalog = clean
        geometry = WheelGeometry(categories: clean.categories)
        loadState = .loaded
    }

    private func startSpin(isForcedRespin: Bool) {
        if isForcedRespin {
            isAwaitingForcedRespin = false
        }
        applyPendingCatalogIfIdle()
        guard canSpin else { return }
        cancelRequested = false
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
        activeSpin = nil
        pendingFinalRotation = nil
        if shortStress {
            duration = Self.stressSpinDuration
            animation = .easeOut(duration: duration)
            crossings = SpinTicks.tickTimes(from: start, to: target, geometry: geometry,
                                            curve: .easeOut, duration: duration, minInterval: 0)
        } else {
            // Timing (not outcome) is locked to the recorded clip.
            let motion = SpinMotion.plan(from: start, to: target, geometry: geometry)
            let control = SpinStopControl()
            duration = motion.duration
            animation = Animation(SpinMotionAnimation(motion: motion, id: token, stop: control))
            crossings = motion.crossingTimes
            activeSpin = (start, target, motion, CACurrentMediaTime(), control, isForcedRespin)
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
        isStopping = false
        spinIsStoppable = activeSpin != nil
        notice = isForcedRespin ? "Re-spin forced! Here we go again…" : nil
        watchdogTask?.cancel()
        watchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration + RouletteViewModel.watchdogGrace))
            guard !Task.isCancelled else { return }
            self?.finishSpin(token: token, wasForcedRespin: isForcedRespin)
        }
    }

    /// Tap to stop: picks a new random landing at least ~1/3 turn ahead and
    /// decelerates to it over ~0.8 s (SpinStopPlan). The spin sound fades out
    /// over the same time and the haptic ticks follow the slowing wheel. The
    /// result is recorded exactly once, by the usual completion/watchdog path.
    public func stopEarly() {
        guard canStop, let spin = activeSpin else { return }
        // Lead slightly: the animation clock starts a hair after `began`, so
        // the next frame is always past the plan's start (no one-frame jump).
        let elapsed = max(0, CACurrentMediaTime() - spin.began - Self.stopLead)
        guard let plan = SpinStopPlan.make(
            motion: spin.motion, start: spin.start, oldTarget: spin.target,
            elapsed: elapsed, geometry: geometry, using: &rng
        ), spin.control.set(plan) else { return }
        isStopping = true
        pendingFinalRotation = plan.newTarget
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { stopOffset = plan.offset }

        // Sound fades over the decel; haptics follow the new, slowing crossings.
        feedback.stopClip(fade: true, duration: SpinStopPlan.duration)
        hapticsTask?.cancel()
        hapticsTask = nil
        if AppSettings.bool(AppSettings.haptics, store: settings) {
            let times = SpinTicks.thinned(plan.crossingTimes(geometry: geometry), minInterval: Self.hapticMinInterval)
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

        let token = spinToken
        let remaining = max(0, plan.endTime - (CACurrentMediaTime() - spin.began))
        spinEndsAt = ContinuousClock.now.advanced(by: .seconds(remaining))
        let wasForced = spin.wasForcedRespin
        watchdogTask?.cancel()
        watchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(remaining + RouletteViewModel.watchdogGrace))
            guard !Task.isCancelled else { return }
            self?.finishSpin(token: token, wasForcedRespin: wasForced)
        }
    }

    /// tvOS Menu during a spin: the spin is called off. The wheel slows to a
    /// stop as for `stopEarly()` (or, if it can't be stopped any more, runs
    /// out), then nothing is revealed or recorded and the last result stays.
    /// A pending forced re-spin is cancelled. iOS never calls this.
    public func cancelSpin() {
        if isAwaitingForcedRespin {
            forcedRespinTask?.cancel()
            forcedRespinTask = nil
            isAwaitingForcedRespin = false
            rareBanner = nil
            notice = nil
            applyPendingCatalogIfIdle()
            return
        }
        guard isSpinning else { return }
        cancelRequested = true
        notice = nil
        if canStop { stopEarly() } else { stopFeedback() }
    }

    public static let stopLead = 0.03
    public static let stressSpinDuration = 0.25
    public static let watchdogGrace = 1.5

    /// Stops the spin sound (fade) and pending haptics: view disappeared or
    /// app went to the background. The spin result itself is unaffected.
    public func stopFeedback() {
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
    public func spinAgain() {
        spinAgainRequested = true
        reveal = nil
    }

    public func revealDismissed() {
        applyPendingCatalogIfIdle()
        guard spinAgainRequested else { return }
        spinAgainRequested = false
        // Next main-actor turn: outside the sheet-dismissal transaction, so the
        // spin's animation (and its completion) is entirely its own.
        Task { @MainActor [weak self] in self?.spin() }
    }

    private func finishSpin(token: Int, wasForcedRespin: Bool) {
        // Exactly once per spin: whichever of completion/watchdog comes first.
        guard isSpinning, token == spinToken else { return }
        defer { isSpinning = false; isStopping = false; spinIsStoppable = false; activeSpin = nil }
        // A stopped spin: fold the offset into `rotation` (same drawn angle).
        if let final = pendingFinalRotation {
            pendingFinalRotation = nil
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                rotation = final
                stopOffset = 0
            }
        }
        watchdogTask?.cancel()
        watchdogTask = nil
        hapticsTask?.cancel()
        hapticsTask = nil
        // Normal spins end on the clip's last thunk (let its decay ring out);
        // short stress spins end early, so fade the clip.
        if stressMode && !stressRealTiming { feedback.stopClip(fade: true) }
        rareBanner = nil
        if cancelRequested {
            cancelRequested = false
            return
        }
        guard let catalog else { return }

        // The winner comes purely from the final angle, using the same geometry the wheel is drawn with.
        let index = geometry.segmentIndex(forRotation: rotation)
        guard catalog.categories.indices.contains(index) else { return }
        let landed = catalog.categories[index]
        lastCategory = landed

        // Rare outcomes (~1% each; always on). Re-spins never chain.
        let policy = RareOutcomePolicy(isEnabled: true)
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
        if isJackpot { notice = "Infamous Jackpot!" }

        let result = SpinResult(movieId: movie.id, categoryId: category.id)
        history.record(result)
        sideEffects.spinRecorded(movie, category, result.timestamp)
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
    public static var stressRealTimingArgument: Bool {
        ProcessInfo.processInfo.arguments.contains("-MRTStressRealTiming")
    }

    /// `-MRTStressSpins N` launch argument (DEBUG builds only).
    public static var stressSpinArgument: Int? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-MRTStressSpins"), args.indices.contains(i + 1),
              let n = Int(args[i + 1]), n > 0 else { return nil }
        return min(n, 10_000)
    }

    /// Unbuffered (stderr) so progress is visible even when output goes to a file.
    public static func stressLog(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    /// Performs `count` rapid spins with a shortened animation, presenting and
    /// auto-dismissing each reveal sheet. Progress goes to stdout as
    /// `MRT-STRESS ...` lines. Nothing else about spinning changes.
    public func runStressSpins(_ count: Int) async {
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
    public static func preview() -> RouletteViewModel {
        RouletteViewModel(
            catalogSource: BundleCatalogSource(),
            history: SpinHistoryStore(fileStore: nil)
        )
    }
}
