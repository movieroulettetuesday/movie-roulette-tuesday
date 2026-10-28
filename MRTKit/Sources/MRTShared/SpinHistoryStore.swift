import Foundation
import Observation
import MRTCore

/// Observable, app-side wrapper around the JSON spin log. Spin counts and
/// "has been spun" are derived from the log via `stats`, never stored on Movie.
///
/// The detailed log is capped (`SpinHistoryLog.defaultDetailLimit`); older
/// spins survive as counts in `archive`, so stats stay exact.
///
/// Apple TV passes `defaults` and `keepsArchive: false`. tvOS can purge
/// Application Support, and the TV stats screen keeps only the last
/// `tvDetailLimit` spins (no archive, no iCloud). iOS keeps the file store
/// and the archive; leave `defaults` nil there.
@MainActor
@Observable
public final class SpinHistoryStore {
    /// Spins kept on Apple TV. Older ones are dropped, not archived.
    public static let tvDetailLimit = 100
    /// UserDefaults key for the TV log. Not used by iOS.
    public static let tvDefaultsKey = "tv.spinHistory"

    /// Recent detailed spins, chronological (oldest first).
    public private(set) var results: [SpinResult] = []
    /// Counts for spins older than the detailed window.
    public private(set) var archive: SpinHistoryArchive = .empty
    /// Cached; recomputed only when the log changes (it's read per row/sort).
    public private(set) var stats = SpinStats(history: [])
    public private(set) var lastError: String?

    private let fileStore: SpinHistoryFileStore?
    private let detailLimit: Int
    /// When set, the log is JSON in UserDefaults and `fileStore` is ignored.
    private let defaults: UserDefaults?
    private let defaultsKey: String
    /// False on Apple TV: overflow is discarded so the total never exceeds `detailLimit`.
    private let keepsArchive: Bool

    /// Pass `fileStore: nil` for an in-memory store (previews, UI tests).
    /// Pass `defaults` (and `keepsArchive: false`) for the Apple TV log.
    public init(
        fileStore: SpinHistoryFileStore? = try? SpinHistoryFileStore.applicationSupport(),
        detailLimit: Int = SpinHistoryLog.defaultDetailLimit,
        defaults: UserDefaults? = nil,
        defaultsKey: String = SpinHistoryStore.tvDefaultsKey,
        keepsArchive: Bool = true
    ) {
        self.fileStore = defaults == nil ? fileStore : nil
        self.detailLimit = detailLimit
        self.defaults = defaults
        self.defaultsKey = defaultsKey
        self.keepsArchive = keepsArchive
        load()
    }

    /// The app's one persistent store. Shared with App Intents (they run in
    /// the app process), so a Siri spin lands in the same history the UI shows.
    public static let shared = SpinHistoryStore()

    public var totalSpins: Int { stats.totalSpins }

    public func record(_ result: SpinResult) {
        var log = SpinHistoryLog(results: results, archive: keepsArchive ? archive : .empty)
        log.append(result, detailLimit: detailLimit)
        if !keepsArchive { log.archive = .empty }
        apply(log)
        persist()
    }

    public func clear() {
        apply(SpinHistoryLog())
        persist()
    }

    private func apply(_ log: SpinHistoryLog) {
        results = log.results
        archive = log.archive
        stats = log.stats
    }

    private func load() {
        if let defaults {
            guard let data = defaults.data(forKey: defaultsKey) else { return }
            do {
                var log = try JSONDecoder().decode(SpinHistoryLog.self, from: data)
                let loadedCount = log.results.count
                let loadedArchive = log.archive
                log.compact(detailLimit: detailLimit)
                if !keepsArchive { log.archive = .empty }
                apply(log)
                if log.results.count != loadedCount || log.archive != loadedArchive { persist() }
            } catch {
                defaults.removeObject(forKey: defaultsKey)
                lastError = "Spin history couldn't be read, so it was reset."
            }
            return
        }
        guard let fileStore else { return }
        do {
            var log = try fileStore.loadLog()
            let before = log.results.count
            log.compact(detailLimit: detailLimit)
            apply(log)
            if log.results.count != before { persist() }
        } catch {
            // Fail soft: move the unreadable file aside (so the next save
            // can't silently destroy it) and start fresh.
            let backup = CorruptFileQuarantine.quarantine(fileStore.fileURL)
            lastError = backup == nil
                ? "Spin history couldn't be read, so it was reset."
                : "Spin history couldn't be read. A backup was kept and history was reset."
        }
    }

    private func persist() {
        let log = SpinHistoryLog(results: results, archive: archive)
        if let defaults {
            do {
                defaults.set(try JSONEncoder().encode(log), forKey: defaultsKey)
                lastError = nil
            } catch {
                lastError = "Couldn’t save spin history: \(error.localizedDescription)"
            }
            return
        }
        guard let fileStore else { return }
        do {
            try fileStore.saveLog(log)
            lastError = nil
        } catch {
            lastError = "Couldn’t save spin history: \(error.localizedDescription)"
        }
    }
}
