import Foundation

/// One external open for a Where-to-Watch tap.
///
/// iOS and tvOS report Cancel on the system confirmation as `false`, the
/// same signal as a URL that could not be opened. The next candidate is a
/// universal link or a custom scheme for the same provider, so opening it
/// after a refusal leaves the app the person chose to stay in.
public enum ProviderOpenPolicy {
    public enum Result: Equatable, Sendable {
        case opened(URL)
        case declined(URL)
        case none
    }

    /// The only URL a tap may hand to the system. Later candidates are not
    /// a fallback.
    public static func urlToOpen(_ urls: [URL]) -> URL? {
        urls.first
    }

    /// Opens `urlToOpen` and stops, whether the system accepts it or not.
    public static func openFirst(
        of urls: [URL],
        using openURL: (URL, @escaping (Bool) -> Void) -> Void,
        completion: @escaping (Result) -> Void = { _ in }
    ) {
        guard let url = urlToOpen(urls) else {
            completion(.none)
            return
        }
        openURL(url) { accepted in
            completion(accepted ? .opened(url) : .declined(url))
        }
    }
}
