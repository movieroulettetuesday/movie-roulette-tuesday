import Foundation

/// Persists the spin log as JSON in a single file (Application Support by
/// default). Synchronous and small on purpose: the log is capped (see
/// `SpinHistoryLog`). Writes are atomic.
public struct SpinHistoryFileStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `<Application Support>/MovieRoulette/spin-history.json`
    public static func applicationSupport(fileManager: FileManager = .default) throws -> SpinHistoryFileStore {
        let base = try fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let url = base
            .appendingPathComponent("MovieRoulette", isDirectory: true)
            .appendingPathComponent("spin-history.json", isDirectory: false)
        return SpinHistoryFileStore(fileURL: url)
    }

    /// Full log (detailed recent spins + archived counts). A missing file
    /// means no history. Accepts the legacy bare-array format.
    public func loadLog() throws -> SpinHistoryLog {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return SpinHistoryLog() }
        let data = try Data(contentsOf: fileURL)
        return try Self.decoder.decode(SpinHistoryLog.self, from: data)
    }

    public func saveLog(_ log: SpinHistoryLog) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let data = try Self.encoder.encode(log)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Detailed results only (oldest first).
    public func load() throws -> [SpinResult] { try loadLog().results }

    public func save(_ results: [SpinResult]) throws { try saveLog(SpinHistoryLog(results: results)) }

    // Default date strategy (seconds since 2001 as a Double) round-trips
    // exactly; ISO-8601 would drop sub-second precision.
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static var decoder: JSONDecoder { JSONDecoder() }
}
