import Foundation

/// App wiring for the movie list: show the cached remote copy (or the bundled
/// `movies.json`) at once, then refresh from GitHub in the background.
enum AppCatalog {
    /// CFBundleVersion; a cache written by another build is ignored.
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    /// DEBUG automation (unit-test host, or any `-MRT…` launch argument used by the
    /// smoke/screenshot UI tests) stays on the bundled list: deterministic and offline.
    static var bundledOnly: Bool {
        #if DEBUG
        let info = ProcessInfo.processInfo
        return info.environment["XCTestConfigurationFilePath"] != nil
            || info.arguments.contains { $0.hasPrefix("-MRT") }
        #else
        return false
        #endif
    }

    static func cache() -> CatalogCache? {
        bundledOnly ? nil : CatalogCache.standard(build: build)
    }

    /// Cached remote copy, else bundled. Never touches the network.
    static func localSource() -> any MovieCatalogSource {
        LocalCatalog.source(cache: cache(), bundled: BundleCatalogSource(resourceName: "movies"))
    }

    /// nil in bundled-only mode (no network refresh).
    static func refresher() -> CatalogRefresher? {
        bundledOnly ? nil : CatalogRefresher(cache: cache())
    }
}
