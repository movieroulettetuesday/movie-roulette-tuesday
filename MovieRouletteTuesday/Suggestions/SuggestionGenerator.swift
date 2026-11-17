import Foundation
import Observation

protocol SuggestionResponding: Sendable {
    /// Loads the model ahead of a tap. Not guaranteed under memory pressure.
    func prewarm()
    /// One answer: a number from the prompt's list and a vibe.
    func pick(prompt: String) async throws -> RawPick
}

extension SuggestionResponding {
    func prewarm() {}
}

/// Shared by the Roulette-tab button and the Pick for Me intent.
/// Tests inject a stub session; the live path uses only `SystemLanguageModel.default`.
@MainActor
enum SuggestionGenerator {
    static var responder: (() -> any SuggestionResponding)?
    /// One attempt, then the app's own pick.
    static var timeout: Duration = .milliseconds(2500)
    /// Tests pin the tie shuffle.
    static var seed: UInt64?
    /// Last tap's timings (DEBUG log and device measurement).
    static private(set) var lastTiming: Timing?

    struct Timing: Equatable, Sendable {
        var promptCharacters: Int
        var modelSeconds: Double?
        var timedOut: Bool
    }

    private static var live: (any SuggestionResponding)?

    static func reset() {
        responder = nil
        timeout = .milliseconds(2500)
        seed = nil
        lastTiming = nil
    }

    /// Called when the Roulette tab appears and the gate is ready.
    static func prewarm() {
        guard SuggestionGate.entry(for: SuggestionAvailability.current()) == .ready else { return }
        #if DEBUG
        if DebugLaunch.suggestionStubbed { return }
        #endif
        currentResponder()?.prewarm()
    }

    static func generate() async -> SuggestionOutcome {
        let status = SuggestionAvailability.current()
        switch SuggestionGate.entry(for: status) {
        case .hidden: return .offerSpin(.unavailable)
        case .notReady: return .notReady
        case .ready: break
        }

        guard let catalog = try? await IntentCatalog.load() else {
            return .offerSpin(.failed)
        }
        let services = MyServices(
            serialized: IntentRuntime.defaults().string(forKey: MyServices.storageKey) ?? ""
        )
        let rows = PickMovie.rows(
            catalog: catalog,
            ratings: IntentRuntime.ratings().ratings,
            recentIDs: SuggestionPrompt.recentIDs(from: IntentRuntime.history().results),
            services: services
        )
        var rng = SeededGenerator(seed: seed ?? UInt64.random(in: .min ... .max))
        var candidates = PickCandidates.select(rows, using: &rng)
        var session = currentResponder()

        #if DEBUG
        if let stub = DebugLaunch.suggestionStub(rows: rows) {
            candidates = stub.candidates(from: candidates)
            session = stub
        }
        #endif

        guard !candidates.isEmpty else { return .offerSpin(.failed) }
        let providerNames = StreamingCatalog.services(in: catalog.movies).map(\.name)
        let prompt = PickPrompt.prompt(for: candidates)

        var raw: RawPick?
        var timing = Timing(promptCharacters: prompt.count, modelSeconds: nil, timedOut: false)
        if let session {
            let clock = ContinuousClock()
            let start = clock.now
            let answer = await firstOf(timeout: timeout) { try await session.pick(prompt: prompt) }
            let elapsed = start.duration(to: clock.now)
            switch answer {
            case .value(let value):
                raw = value
                timing.modelSeconds = Self.seconds(elapsed)
            case .failed:
                timing.modelSeconds = Self.seconds(elapsed)
            case .timedOut:
                timing.timedOut = true
            }
        }
        lastTiming = timing
        #if DEBUG
        FileHandle.standardError.write(Data(
            "MRT-PICK chars=\(timing.promptCharacters) model=\(timing.modelSeconds.map { String(format: "%.3f", $0) } ?? "-") timedOut=\(timing.timedOut)\n".utf8
        ))
        #endif

        let resolution = PickResolver.resolve(raw, candidates: candidates, providerNames: providerNames)
        guard let accepted = PickResolver.accept(resolution, candidates: candidates) else {
            return .offerSpin(.failed)
        }
        return .suggestion(accepted)
    }

    enum Answer<T: Sendable>: Sendable {
        case value(T)
        case failed
        case timedOut
    }

    /// Returns at the timeout even if the model ignores cancellation (the
    /// abandoned call is cancelled and its answer dropped).
    static func firstOf<T: Sendable>(
        timeout: Duration,
        _ operation: @escaping @Sendable () async throws -> T
    ) async -> Answer<T> {
        let once = ResumeOnce<Answer<T>>()
        return await withCheckedContinuation { continuation in
            once.install(continuation)
            let work = Task {
                do { once.resume(.value(try await operation())) } catch { once.resume(.failed) }
            }
            Task {
                try? await Task.sleep(for: timeout)
                work.cancel()
                once.resume(.timedOut)
            }
        }
    }

    private static func seconds(_ d: Duration) -> Double {
        Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }

    private static func currentResponder() -> (any SuggestionResponding)? {
        if let responder { return responder() }
        if let live { return live }
        live = defaultResponder()
        return live
    }

    static func defaultResponder() -> (any SuggestionResponding)? {
        if #available(iOS 26.0, *) {
            return systemResponder()
        }
        return nil
    }

    @available(iOS 26.0, *)
    private static func systemResponder() -> (any SuggestionResponding)? {
        #if canImport(FoundationModels)
        return OnDeviceSuggestionSession()
        #else
        return nil
        #endif
    }
}

/// Resumes a continuation once; later calls are ignored.
final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?
    private var pending: T?
    private var done = false

    func install(_ c: CheckedContinuation<T, Never>) {
        lock.lock()
        if let pending, !done {
            done = true
            lock.unlock()
            c.resume(returning: pending)
            return
        }
        continuation = c
        lock.unlock()
    }

    func resume(_ value: T) {
        lock.lock()
        guard !done else { lock.unlock(); return }
        guard let c = continuation else { pending = value; lock.unlock(); return }
        done = true
        continuation = nil
        lock.unlock()
        c.resume(returning: value)
    }
}

@MainActor
@Observable
final class SuggestionController {
    var entry: SuggestionEntry = .hidden
    var outcome: SuggestionOutcome?
    var isLoading = false
    var presented = false

    var showsButton: Bool { entry != .hidden }

    func refresh() {
        entry = SuggestionGate.entry(for: SuggestionAvailability.current())
    }

    /// Roulette tab appeared: load the model before the first tap.
    func prewarm() {
        refresh()
        if entry == .ready { SuggestionGenerator.prewarm() }
    }

    func tap() async {
        // Set the visible state before presenting so a form-sized sheet
        // doesn't first land on an empty ProgressView and collapse.
        refresh()
        switch entry {
        case .hidden:
            isLoading = false
            outcome = .offerSpin(.unavailable)
        case .notReady:
            isLoading = false
            outcome = .notReady
        case .ready:
            isLoading = true
            outcome = nil
        }
        presented = true
        guard entry == .ready else { return }
        tapID += 1
        let id = tapID
        let result = await SuggestionGenerator.generate()
        // Cancelled (or tapped again) while loading: drop this answer.
        guard id == tapID, presented else { return }
        outcome = result
        isLoading = false
    }

    @ObservationIgnored private var tapID = 0

    func dismiss() {
        tapID += 1
        presented = false
        outcome = nil
        isLoading = false
    }
}
