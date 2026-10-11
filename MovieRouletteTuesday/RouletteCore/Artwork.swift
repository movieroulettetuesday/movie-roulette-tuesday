import Foundation

/// Picks artwork for movies and episodes (pure; UI-free, also compiled into
/// the widget, which never loads images).
///
/// Order for a movie: the earliest of its episodes that has artwork, then the
/// catalog `posterURL`, then the show artwork. An empty result means "use the
/// placeholder". The view tries the URLs in order, so a broken episode image
/// still falls back to the show art.
public enum ArtworkResolver {
    /// http(s) URL with a host, or nil. Anything else (empty, relative,
    /// `file:`, `javascript:`) is never handed to the image loader.
    public static func usableURL(_ raw: String?) -> URL? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
        return usableURL(url)
    }

    public static func usableURL(_ url: URL?) -> URL? {
        guard let url, let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// The movie's earliest episode that has artwork. "Earliest" is by
    /// publish date; undated episodes come after dated ones, in catalog order.
    public static func episodeArtwork(
        for movie: Movie,
        episodesByGUID: [String: PodcastEpisode]
    ) -> (guid: String, url: URL)? {
        var best: (guid: String, url: URL, date: Date, index: Int)?
        for (index, guid) in movie.episodeIds.enumerated() {
            guard let episode = episodesByGUID[guid], let url = usableURL(episode.imageURL) else { continue }
            let date = episode.pubDate ?? .distantFuture
            if let current = best, (current.date, current.index) <= (date, index) { continue }
            best = (guid, url, date, index)
        }
        return best.map { ($0.guid, $0.url) }
    }

    /// URLs to try, best first, without duplicates. Empty -> placeholder.
    public static func candidates(
        for movie: Movie,
        episodesByGUID: [String: PodcastEpisode],
        showArtwork: URL?
    ) -> [URL] {
        unique([
            episodeArtwork(for: movie, episodesByGUID: episodesByGUID)?.url,
            usableURL(movie.posterURL),
            usableURL(showArtwork),
        ])
    }

    /// An episode's own art, then the show art.
    public static func candidates(for episode: PodcastEpisode, showArtwork: URL?) -> [URL] {
        unique([usableURL(episode.imageURL), usableURL(showArtwork)])
    }

    private static func unique(_ urls: [URL?]) -> [URL] {
        var seen = Set<URL>()
        return urls.compactMap { $0 }.filter { seen.insert($0).inserted }
    }
}

/// Decode sizes for artwork. Images are downsampled to the pixels actually
/// shown (a 1400 px feed image is ~7.8 MB decoded; a 44 pt @3x row
/// thumbnail needs 132 px, ~70 KB).
public enum ArtworkSizing {
    public static let minPixels = 16
    public static let maxPixels = 1024

    public static func maxPixelSize(points: Double, scale: Double) -> Int {
        let pixels = points * scale
        guard pixels.isFinite, pixels > 0 else { return minPixels }
        return min(max(Int(pixels.rounded(.up)), minPixels), maxPixels)
    }

    /// Bytes for a decoded RGBA image of that size (the memory-cache cost).
    public static func decodedBytes(width: Int, height: Int) -> Int {
        max(0, width) * max(0, height) * 4
    }
}

/// Navigation inside the Movies tab: a movie page can push one of its
/// episodes, so back returns to the movie.
public enum MoviesRoute: Hashable, Sendable {
    case movie(String)
    case episode(String)

    public var movieID: String? {
        if case .movie(let id) = self { return id }
        return nil
    }
}

/// Keeps Movies navigation intact when the size class changes (iPad Split
/// View / rotation). Compact uses one stack path `[.movie(id), .episode(guid)…]`.
/// Regular uses a split-view selection plus the detail column's own stack,
/// which belongs to the movie it was pushed from.
public enum MoviesNavigation {
    public struct Regular: Equatable, Sendable {
        public var selectedMovieID: String?
        /// Routes pushed in the detail column on top of the selected movie.
        public var detailPath: [MoviesRoute]

        public init(selectedMovieID: String?, detailPath: [MoviesRoute] = []) {
            self.selectedMovieID = selectedMovieID
            self.detailPath = detailPath
        }
    }

    /// Split view -> stack.
    public static func compactPath(from regular: Regular) -> [MoviesRoute] {
        guard let id = regular.selectedMovieID else { return [] }
        return [.movie(id)] + regular.detailPath
    }

    /// Stack -> split view: the deepest movie becomes the selection and
    /// whatever was pushed above it stays in the detail column.
    public static func regular(fromCompactPath path: [MoviesRoute]) -> Regular {
        guard let index = path.lastIndex(where: { $0.movieID != nil }),
              let id = path[index].movieID else {
            return Regular(selectedMovieID: nil)
        }
        return Regular(selectedMovieID: id, detailPath: Array(path[(index + 1)...]))
    }
}

/// Where a Spin History row leads: the spun movie's episode page (the first of
/// the movie's `episodeIds` present in the feed, the same ids the movie page
/// links), else the movie page, else nowhere (row isn't tappable).
public enum SpinHistoryRouting {
    public static func destination(
        for spin: SpinResult,
        catalog: MovieCatalog?,
        episodesByGUID: [String: PodcastEpisode]
    ) -> MoviesRoute? {
        guard let movie = catalog?.movie(withId: spin.movieId) else { return nil }
        if let guid = movie.episodeIds.first(where: { episodesByGUID[$0] != nil }) {
            return .episode(guid)
        }
        return .movie(movie.id)
    }
}
