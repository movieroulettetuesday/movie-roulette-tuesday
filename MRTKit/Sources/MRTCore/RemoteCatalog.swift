import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Where the live movie list lives. `movies.json` on the GitHub repo's `main`
/// branch is the source of truth; the copy bundled in the app is the fallback.
public enum RemoteCatalog {
    public static let url = URL(string:
        "https://raw.githubusercontent.com/movieroulettetuesday/movie-roulette-tuesday/main/MovieRouletteTuesday/Resources/movies.json")!
    /// Short on purpose: the refresh runs in the background and is best-effort.
    public static let timeout: TimeInterval = 8
}

// MARK: - Validation

public enum CatalogValidationError: Error, Equatable, LocalizedError {
    case unsupportedSchema(Int)
    case empty
    case inconsistent([String])

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let v): return "The movie list uses an unsupported format (schema \(v))."
        case .empty: return "The movie list is empty."
        case .inconsistent(let issues): return "The movie list has problems: \(issues.prefix(3).joined(separator: "; "))"
        }
    }
}

/// A catalog only replaces what the app already has when it decodes, uses a
/// schema this build understands, is non-empty, and is fully consistent
/// (`validationIssues()` empty: no unknown ids, no empty wheel slices, bad colors).
public enum CatalogValidator {
    public static let supportedSchemaVersions = 1...2

    @discardableResult
    public static func validate(_ catalog: MovieCatalog) throws -> MovieCatalog {
        guard supportedSchemaVersions.contains(catalog.schemaVersion) else {
            throw CatalogValidationError.unsupportedSchema(catalog.schemaVersion)
        }
        guard !catalog.movies.isEmpty, !catalog.categories.isEmpty else { throw CatalogValidationError.empty }
        let issues = catalog.validationIssues()
        guard issues.isEmpty else { throw CatalogValidationError.inconsistent(issues) }
        return catalog
    }

    public static func decodeValidated(_ data: Data) throws -> MovieCatalog {
        try validate(MovieCatalog.decode(from: data))
    }
}

/// Wraps any source and rejects catalogs that fail `CatalogValidator`.
public struct ValidatingCatalogSource<Base: MovieCatalogSource>: MovieCatalogSource {
    public let base: Base
    public init(_ base: Base) { self.base = base }
    public func loadCatalog() async throws -> MovieCatalog {
        try CatalogValidator.validate(await base.loadCatalog())
    }
}

// MARK: - On-device cache

/// The last good remote `movies.json`, stored as the raw bytes that passed
/// validation, plus a small sidecar recording which app build wrote it.
/// A cache written by a different build is ignored (after an app update the
/// bundled list may be newer; the next refresh repopulates the cache).
/// Lives in the App Group container so the widget can read it too.
public struct CatalogCache: Sendable {
    public static let fileName = "movies-remote-cache.json"
    public let fileURL: URL
    public let build: String

    struct Meta: Codable, Equatable {
        var build: String
        var fetchedAt: Date
    }

    public init(fileURL: URL, build: String) {
        self.fileURL = fileURL
        self.build = build
    }

    var metaURL: URL { fileURL.appendingPathExtension("meta") }

    /// App Group container when available (shared with the widget), else the
    /// app's Application Support directory. nil off Apple platforms.
    public static func standard(build: String) -> CatalogCache? {
        #if canImport(Darwin)
        let fm = FileManager.default
        if let group = fm.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier) {
            return CatalogCache(fileURL: group.appendingPathComponent(fileName), build: build)
        }
        guard let support = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                        appropriateFor: nil, create: true) else { return nil }
        return CatalogCache(fileURL: support.appendingPathComponent(fileName), build: build)
        #else
        return nil
        #endif
    }

    /// Cached bytes, or nil when missing or written by another build.
    public func loadData() -> Data? {
        guard let metaData = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode(Meta.self, from: metaData),
              meta.build == build else { return nil }
        return try? Data(contentsOf: fileURL)
    }

    /// When the cached copy was fetched (nil when there's no usable cache).
    public var fetchedAt: Date? {
        guard let metaData = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode(Meta.self, from: metaData),
              meta.build == build, FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return meta.fetchedAt
    }

    /// Validated catalog from the cache, or nil.
    public func loadCatalog() -> MovieCatalog? {
        loadData().flatMap { try? CatalogValidator.decodeValidated($0) }
    }

    public func save(_ data: Data, fetchedAt: Date = Date()) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        try JSONEncoder().encode(Meta(build: build, fetchedAt: fetchedAt)).write(to: metaURL, options: .atomic)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: metaURL)
    }
}

/// Reads the cached remote catalog; throws when there is no valid cache.
public struct CacheCatalogSource: MovieCatalogSource {
    public let cache: CatalogCache?
    public init(cache: CatalogCache?) { self.cache = cache }
    public func loadCatalog() async throws -> MovieCatalog {
        guard let catalog = cache?.loadCatalog() else { throw CatalogLoadingError.resourceNotFound(CatalogCache.fileName) }
        return catalog
    }
}

// MARK: - Local load + background refresh

public enum LocalCatalog {
    /// What the app shows immediately, with no network: the last good remote
    /// copy if there is one, else the bundled `movies.json`.
    public static func source<Bundled: MovieCatalogSource>(cache: CatalogCache?, bundled: Bundled)
        -> FallbackCatalogSource<CacheCatalogSource, Bundled> {
        FallbackCatalogSource(primary: CacheCatalogSource(cache: cache), fallback: bundled)
    }

    /// Synchronous version for the widget: cache, else the bundle's `movies.json`.
    public static func loadSync(cache: CatalogCache?, bundle: Bundle = .main) -> MovieCatalog? {
        if let cached = cache?.loadCatalog() { return cached }
        guard let url = bundle.url(forResource: "movies", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? MovieCatalog.decode(from: data)
    }
}

/// Fetches the remote catalog, validates it, and only then replaces the cache.
/// Any failure (offline, timeout, HTTP error, bad JSON, failed validation)
/// throws and leaves the cache untouched.
public struct CatalogRefresher: Sendable {
    public let remote: RemoteCatalogSource
    public let cache: CatalogCache?

    public init(remote: RemoteCatalogSource = RemoteCatalogSource(url: RemoteCatalog.url), cache: CatalogCache?) {
        self.remote = remote
        self.cache = cache
    }

    public func refresh(now: Date = Date()) async throws -> MovieCatalog {
        let data = try await remote.fetchData()
        let catalog = try CatalogValidator.decodeValidated(data)
        try? cache?.save(data, fetchedAt: now)
        return catalog
    }
}
