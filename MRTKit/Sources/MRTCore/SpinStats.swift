import Foundation

/// Per-device numbers derived from spin history (never stored on `Movie`).
/// Includes spins that were compacted into a `SpinHistoryArchive`.
public struct SpinStats: Equatable, Sendable {
    public let totalSpins: Int
    private let movieCounts: [String: Int]
    private let categoryCounts: [String: Int]

    public init(history: [SpinResult], archive: SpinHistoryArchive = .empty) {
        totalSpins = archive.totalSpins + history.count
        var movies = archive.movieCounts
        var categories = archive.categoryCounts
        for spin in history {
            movies[spin.movieId, default: 0] += 1
            categories[spin.categoryId, default: 0] += 1
        }
        movieCounts = movies
        categoryCounts = categories
    }

    public func spinCount(forMovie id: String) -> Int { movieCounts[id, default: 0] }
    public func hasBeenSpun(movie id: String) -> Bool { spinCount(forMovie: id) > 0 }
    public func spinCount(forCategory id: String) -> Int { categoryCounts[id, default: 0] }
    public var distinctMoviesSpun: Int { movieCounts.count }
}
