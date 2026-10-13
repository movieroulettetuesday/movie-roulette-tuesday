import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Anything that can produce a `MovieCatalog`. The app depends only on this
/// protocol. The app loads `LocalCatalog.source` (cached remote copy, else the
/// bundled JSON) and refreshes from `RemoteCatalog.url` in the background.
public protocol MovieCatalogSource: Sendable {
    func loadCatalog() async throws -> MovieCatalog
}

public enum CatalogLoadingError: Error, LocalizedError, Equatable {
    case resourceNotFound(String)
    case badHTTPStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .resourceNotFound(let name): return "Couldn't find \(name) in the app bundle."
        case .badHTTPStatus(let code): return "The server responded with HTTP \(code)."
        }
    }
}

extension MovieCatalog {
    public static func decode(from data: Data) throws -> MovieCatalog {
        try JSONDecoder().decode(MovieCatalog.self, from: data)
    }
}

/// Reads a catalog from raw bytes (tests, previews).
public struct DataCatalogSource: MovieCatalogSource {
    public let data: Data
    public init(data: Data) { self.data = data }
    public func loadCatalog() async throws -> MovieCatalog { try MovieCatalog.decode(from: data) }
}

/// Reads a catalog from a local file URL.
public struct FileCatalogSource: MovieCatalogSource {
    public let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }
    public func loadCatalog() async throws -> MovieCatalog {
        try MovieCatalog.decode(from: Data(contentsOf: fileURL))
    }
}

/// Reads `movies.json` (by default) from an app bundle.
public struct BundleCatalogSource: MovieCatalogSource {
    public let resourceName: String
    private let url: URL?

    public init(resourceName: String = "movies", bundle: Bundle = .main) {
        self.resourceName = resourceName
        // Resolve now so the source only stores a Sendable URL.
        self.url = bundle.url(forResource: resourceName, withExtension: "json")
    }

    public func loadCatalog() async throws -> MovieCatalog {
        guard let url else { throw CatalogLoadingError.resourceNotFound("\(resourceName).json") }
        return try await FileCatalogSource(fileURL: url).loadCatalog()
    }
}

/// Fetches the catalog from a server (see `RemoteCatalog.url`) with a short
/// timeout, no cookies and no HTTP cache. `fetch` is injectable for tests.
public struct RemoteCatalogSource: MovieCatalogSource {
    public typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public let url: URL
    public let timeout: TimeInterval
    private let fetch: Fetch

    public init(url: URL, timeout: TimeInterval = RemoteCatalog.timeout, fetch: Fetch? = nil) {
        self.url = url
        self.timeout = timeout
        self.fetch = fetch ?? { request in try await RemoteCatalogSource.session.data(for: request) }
    }

    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = RemoteCatalog.timeout
        config.timeoutIntervalForResource = RemoteCatalog.timeout * 2
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieStorage = nil
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    /// Raw response body after an HTTP status check.
    public func fetchData() async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "GET"
        let (data, response) = try await fetch(request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CatalogLoadingError.badHTTPStatus(http.statusCode)
        }
        return data
    }

    /// Decoded and validated (see `CatalogValidator`).
    public func loadCatalog() async throws -> MovieCatalog {
        try CatalogValidator.decodeValidated(await fetchData())
    }
}

/// Tries `primary`, falling back to `fallback` on any error
/// (e.g. remote first, bundled JSON when offline).
public struct FallbackCatalogSource<Primary: MovieCatalogSource, Fallback: MovieCatalogSource>: MovieCatalogSource {
    public let primary: Primary
    public let fallback: Fallback
    public init(primary: Primary, fallback: Fallback) {
        self.primary = primary
        self.fallback = fallback
    }

    public func loadCatalog() async throws -> MovieCatalog {
        do { return try await primary.loadCatalog() } catch { return try await fallback.loadCatalog() }
    }
}
