import Foundation
import Observation
import MRTCore

/// Observable, app-side wrapper around the JSON spin log. Spin counts and
/// "has been spun" are derived from the log via `stats`, never stored on Movie.
///
/// The detailed log is capped (`SpinHistoryLog.defaultDetailLimit`); older
/// spins survive as counts in `archive`, so stats stay exact.
@MainActor
@Observable
final class SpinHistoryStore {
    /// Recent detailed spins, chronological (oldest first).
    private(set) var results: [SpinResult] = []
    /// Counts for spins older than the detailed window.
    private(set) var archive: SpinHistoryArchive = .empty
    /// Cached; recomputed only when the log changes (it's read per row/sort).
    private(set) var stats = SpinStats(history: [])
    private(set) var lastError: String?

    private let fileStore: SpinHistoryFileStore?
    private let detailLimit: Int

    /// Pass `nil` for an in-memory store (previews, UI tests).
    init(
        fileStore: SpinHistoryFileStore? = try? SpinHistoryFileStore.applicationSupport(),
        detailLimit: Int = SpinHistoryLog.defaultDetailLimit
    ) {
        self.fileStore = fileStore
        self.detailLimit = detailLimit
        load()
    }

    /// The app's one persistent store. Shared with App Intents (they run in
    /// the app process), so a Siri spin lands in the same history the UI shows.
    static let shared = SpinHistoryStore()

    var totalSpins: Int { stats.totalSpins }

    func record(_ result: SpinResult) {
        var log = SpinHistoryLog(results: results, archive: archive)
        log.append(result, detailLimit: detailLimit)
        apply(log)
        persist()
    }

    func clear() {
        apply(SpinHistoryLog())
        persist()
    }

    private func apply(_ log: SpinHistoryLog) {
        results = log.results
        archive = log.archive
        stats = log.stats
    }

    private func load() {
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
        guard let fileStore else { return }
        do {
            try fileStore.saveLog(SpinHistoryLog(results: results, archive: archive))
            lastError = nil
        } catch {
            lastError = "Couldn’t save spin history: \(error.localizedDescription)"
        }
    }
}
