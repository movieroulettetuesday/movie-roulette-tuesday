import AVFoundation
import QuartzCore
#if os(iOS)
import UIKit
#endif
import MRTCore

/// Spin sound + crossing haptics.
///
/// Sound: Walter's recorded wheel spin (`wheel-spin.m4a`) plays once per
/// spin, from the spin's first frame; the wheel's motion is timed to it
/// (`SpinMotion`), so each click lands as a slice boundary passes the
/// pointer and the wheel stops on the final thunk. Every audio call (session
/// setup, player creation, `play()`, `stop()`) runs on `SpinAudio`'s serial
/// queue, never on the main thread. The `.ambient` session respects the
/// Ring/Silent switch and mixes with whatever else is playing.
///
/// Haptics: a selection tick for each boundary crossing, on the main actor.
/// tvOS has no haptics: `haptics` and `crossing()` are no-ops there.
@MainActor
public final class SpinFeedback {
    private let audio = SpinAudio()
    #if os(iOS)
    private var selection: UISelectionFeedbackGenerator?
    #endif

    public init() {}

    /// Call right before a spin. With sound off, the audio session is never touched.
    public func prepare(sound: Bool, haptics: Bool) {
        if sound { audio.prepare() }
        #if os(iOS)
        if haptics {
            if selection == nil { selection = UISelectionFeedbackGenerator() }
            selection?.prepare()
        }
        #endif
    }

    /// Starts the spin clip. `startedAt` is the spin's start (`CACurrentMediaTime`),
    /// so a late start (queue hop, session activation) seeks to stay in sync.
    public func startClip(startedAt: CFTimeInterval) {
        audio.play(startedAt: startedAt)
    }

    /// Fades out (or cuts) the clip: spin interrupted, view gone, app backgrounded.
    public func stopClip(fade: Bool = true, duration: TimeInterval = SpinAudio.fadeDuration) {
        audio.stop(fade: fade, duration: duration)
    }

    /// One selection haptic (a boundary crossing).
    public func crossing() {
        #if os(iOS)
        guard let selection else { return }
        selection.selectionChanged()
        selection.prepare()
        #endif
    }
}

/// Owns the audio session activation and one prepared player for the clip.
/// Thread safety: all mutable state is touched only on `queue` (serial), which
/// is why the class can be `@unchecked Sendable`.
public final class SpinAudio: @unchecked Sendable {
    private enum SessionState { case inactive, activating, active }

    public static let fadeDuration: TimeInterval = 0.15
    public static let volume: Float = 0.9

    private let queue = DispatchQueue(label: "com.movieroulettetuesday.spin-audio", qos: .userInteractive)
    private var player: AVAudioPlayer?
    private var categorySet = false
    private var session: SessionState = .inactive
    /// Start time of a clip requested while the session was still activating.
    private var pendingStart: CFTimeInterval?
    /// Bumped on every play/stop so a stale delayed stop is ignored.
    private var generation = 0
    private var observers: [NSObjectProtocol] = []

    public init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: nil
        ) { [weak self] _ in
            // Began or ended: the session is no longer active for us; the next
            // prepare() reactivates it (asynchronously, off main).
            guard let self else { return }
            self.queue.async {
                self.session = .inactive
                self.pendingStart = nil
            }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil
        ) { [weak self] _ in
            // The player and session state are invalid after a reset: rebuild lazily.
            guard let self else { return }
            self.queue.async {
                self.player = nil
                self.categorySet = false
                self.session = .inactive
                self.pendingStart = nil
            }
        })
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    /// Configure + activate the session once and prepare the player, all off main.
    public func prepare() {
        queue.async { [self] in
            activateSessionIfNeeded()
            loadPlayerIfNeeded()
        }
    }

    /// Plays the whole clip once, from the position matching `startedAt`.
    public func play(startedAt: CFTimeInterval) {
        queue.async { [self] in
            // Never on the main thread (Debug builds trap if this regresses).
            dispatchPrecondition(condition: .onQueue(queue))
            generation &+= 1
            loadPlayerIfNeeded()
            guard session == .active else {
                pendingStart = startedAt  // played (in sync) once activation finishes
                activateSessionIfNeeded()
                return
            }
            start(startedAt: startedAt)
        }
    }

    /// Fades the clip out (`fade`) or stops it at once.
    public func stop(fade: Bool, duration: TimeInterval = SpinAudio.fadeDuration) {
        queue.async { [self] in
            dispatchPrecondition(condition: .onQueue(queue))
            pendingStart = nil
            generation &+= 1
            guard let player, player.isPlaying else { return }
            guard fade else {
                player.stop()
                return
            }
            let token = generation
            player.setVolume(0, fadeDuration: duration)
            queue.asyncAfter(deadline: .now() + duration + 0.02) { [self] in
                guard token == generation, let player = self.player else { return }
                player.stop()
                player.volume = Self.volume
            }
        }
    }

    // MARK: - Queue-confined

    private func start(startedAt: CFTimeInterval) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard let player else { return }
        let offset = max(0, CACurrentMediaTime() - startedAt)
        // Too late to be worth hearing (e.g. a very slow activation): stay quiet.
        guard offset < SpinSoundTrack.stopTime - 0.5 else { return }
        player.stop()
        player.volume = Self.volume
        player.currentTime = offset
        player.play()
#if DEBUG
        DebugAudioLog.clipStarted(offset: offset)
#endif
    }

    private func activateSessionIfNeeded() {
        dispatchPrecondition(condition: .onQueue(queue))
        guard session == .inactive else { return }
        let audioSession = AVAudioSession.sharedInstance()
        if !categorySet {
            do {
                try audioSession.setCategory(.ambient, mode: .default, options: [])
                categorySet = true
            } catch {
                return  // no sound this time; haptics are unaffected
            }
        }
        session = .activating
        #if os(iOS)
        if #available(iOS 27.0, *) {
            audioSession.activate(options: []) { [self] activated, _ in
                queue.async { self.sessionActivated(activated) }
            }
        } else {
            // iOS 17–26: synchronous API, but on this background queue.
            sessionActivated((try? audioSession.setActive(true)) != nil)
        }
        #else
        // tvOS: the synchronous API, on this background queue.
        sessionActivated((try? audioSession.setActive(true)) != nil)
        #endif
    }

    private func sessionActivated(_ activated: Bool) {
        dispatchPrecondition(condition: .onQueue(queue))
        session = activated ? .active : .inactive
        if activated, let pending = pendingStart {
            pendingStart = nil
            start(startedAt: pending)
        }
    }

    private func loadPlayerIfNeeded() {
        dispatchPrecondition(condition: .onQueue(queue))
        guard player == nil,
              let url = Bundle.main.url(forResource: SpinSoundTrack.resourceName,
                                        withExtension: SpinSoundTrack.resourceExtension),
              let loaded = try? AVAudioPlayer(contentsOf: url) else { return }
        loaded.volume = Self.volume
        loaded.prepareToPlay()
        player = loaded
    }
}

#if DEBUG
/// `MRT-AUDIO` lines for the audit (clip started, on which thread).
public enum DebugAudioLog {
    public static func clipStarted(offset: TimeInterval) {
        let line = String(format: "MRT-AUDIO clip start offset=%.3f main=%@\n",
                          offset, Thread.isMainThread ? "YES" : "NO")
        FileHandle.standardError.write(Data(line.utf8))
    }
}
#endif
