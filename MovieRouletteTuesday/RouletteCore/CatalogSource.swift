import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Anything that can produce a `MovieCatalog`. The app depends only on this
/// protocol, so the bundled JSON can later be swapped for a remote URL (or a
/// remote-with-bundled-fallback source) without touching UI code.
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

/// Fetches the catalog from a server. Not used yet; here so the swap is trivial.
public struct RemoteCatalogSource: MovieCatalogSource {
    public let url: URL
    public init(url: URL) { self.url = url }

    public func loadCatalog() async throws -> MovieCatalog {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CatalogLoadingError.badHTTPStatus(http.statusCode)
        }
        return try MovieCatalog.decode(from: data)
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
