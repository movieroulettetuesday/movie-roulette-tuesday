import Foundation

/// Per-movie / per-category counts of spins that were compacted out of the
/// detailed history. Keeps "×N" counts, "Haven't spun yet" and the Stats tab
/// correct forever while the detailed log stays bounded.
public struct SpinHistoryArchive: Codable, Equatable, Sendable {
    public var totalSpins: Int
    public var movieCounts: [String: Int]
    public var categoryCounts: [String: Int]

    public static let empty = SpinHistoryArchive()

    public init(totalSpins: Int = 0, movieCounts: [String: Int] = [:], categoryCounts: [String: Int] = [:]) {
        self.totalSpins = max(0, totalSpins)
        self.movieCounts = movieCounts
        self.categoryCounts = categoryCounts
    }

    public mutating func absorb<S: Sequence>(_ results: S) where S.Element == SpinResult {
        for spin in results {
            totalSpins += 1
            movieCounts[spin.movieId, default: 0] += 1
            categoryCounts[spin.categoryId, default: 0] += 1
        }
    }

    // Tolerant decoding: missing fields default to empty.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalSpins = max(0, (try? c.decodeIfPresent(Int.self, forKey: .totalSpins)) ?? 0)
        movieCounts = (try? c.decodeIfPresent([String: Int].self, forKey: .movieCounts)) ?? [:]
        categoryCounts = (try? c.decodeIfPresent([String: Int].self, forKey: .categoryCounts)) ?? [:]
    }

    private enum CodingKeys: String, CodingKey { case totalSpins, movieCounts, categoryCounts }
}

/// The on-disk spin log: the most recent `detailLimit` spins in full, plus
/// aggregate counts for everything older.
///
/// File format v2 is `{"version":2,"results":[...],"archive":{...}}`. The
/// original format (a bare JSON array of results) still loads.
public struct SpinHistoryLog: Codable, Equatable, Sendable {
    public static let currentVersion = 2
    /// Detailed entries kept. Selection only looks at the last few spins and
    /// the history screen at most a few hundred, so 500 is generous.
    public static let defaultDetailLimit = 500

    public var version: Int
    /// Chronological, oldest first.
    public var results: [SpinResult]
    public var archive: SpinHistoryArchive

    public init(results: [SpinResult] = [], archive: SpinHistoryArchive = .empty) {
        self.version = Self.currentVersion
        self.results = results
        self.archive = archive
    }

    public var stats: SpinStats { SpinStats(history: results, archive: archive) }
    public var totalSpins: Int { archive.totalSpins + results.count }

    public mutating func append(_ result: SpinResult, detailLimit: Int = defaultDetailLimit) {
        results.append(result)
        compact(detailLimit: detailLimit)
    }

    /// Moves the oldest entries beyond `detailLimit` into the archive counts.
    public mutating func compact(detailLimit: Int = defaultDetailLimit) {
        let limit = max(0, detailLimit)
        guard results.count > limit else { return }
        let overflow = results.count - limit
        archive.absorb(results.prefix(overflow))
        results.removeFirst(overflow)
    }

    private enum CodingKeys: String, CodingKey { case version, results, archive }

    /// Accepts both the v2 object and the legacy bare array. Individual
    /// malformed entries are skipped rather than failing the whole file.
    public init(from decoder: Decoder) throws {
        if var array = try? decoder.unkeyedContainer() {
            results = try Self.decodeLossy(&array)
            archive = .empty
            version = Self.currentVersion
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decodeIfPresent(Int.self, forKey: .version)) ?? Self.currentVersion
        if var array = try? c.nestedUnkeyedContainer(forKey: .results) {
            results = try Self.decodeLossy(&array)
        } else {
            results = []
        }
        archive = (try? c.decodeIfPresent(SpinHistoryArchive.self, forKey: .archive)) ?? .empty
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.currentVersion, forKey: .version)
        try c.encode(results, forKey: .results)
        try c.encode(archive, forKey: .archive)
    }

    private struct Lossy: Decodable {
        let value: SpinResult?
        init(from decoder: Decoder) throws { value = try? SpinResult(from: decoder) }
    }

    private static func decodeLossy(_ array: inout UnkeyedDecodingContainer) throws -> [SpinResult] {
        var out: [SpinResult] = []
        while !array.isAtEnd {
            if let item = try array.decode(Lossy.self).value { out.append(item) }
        }
        return out
    }
}

/// Moves an unreadable data file aside (`name.corrupt-<timestamp>.ext`) so the
/// app can start fresh without silently overwriting it. Keeps the newest few.
public enum CorruptFileQuarantine {
    public static let keepBackups = 3

    @discardableResult
    public static func quarantine(_ url: URL, now: Date = Date(), fileManager: FileManager = .default) -> URL? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let dir = url.deletingLastPathComponent()
        var backup = dir.appendingPathComponent("\(base).corrupt-\(formatter.string(from: now))")
        if !ext.isEmpty { backup.appendPathExtension(ext) }
        var n = 1
        while fileManager.fileExists(atPath: backup.path) {
            backup = dir.appendingPathComponent("\(base).corrupt-\(formatter.string(from: now))-\(n)")
            if !ext.isEmpty { backup.appendPathExtension(ext) }
            n += 1
        }
        do {
            try fileManager.moveItem(at: url, to: backup)
        } catch {
            // Couldn't move it: last resort, drop it so the app can't get stuck.
            try? fileManager.removeItem(at: url)
            return nil
        }
        prune(base: base, in: dir, fileManager: fileManager)
        return backup
    }

    public static func backups(for url: URL, fileManager: FileManager = .default) -> [URL] {
        let base = url.deletingPathExtension().lastPathComponent
        let dir = url.deletingLastPathComponent()
        let names = (try? fileManager.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { $0.hasPrefix("\(base).corrupt-") }.sorted().map { dir.appendingPathComponent($0) }
    }

    private static func prune(base: String, in dir: URL, fileManager: FileManager) {
        let all = backups(for: dir.appendingPathComponent(base), fileManager: fileManager)
        guard all.count > keepBackups else { return }
        for old in all.prefix(all.count - keepBackups) { try? fileManager.removeItem(at: old) }
    }
}
