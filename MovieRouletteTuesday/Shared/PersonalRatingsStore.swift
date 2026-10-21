import Foundation
import Observation
import MRTCore
import MRTShared

/// Observable wrapper around the local personal-ratings JSON (Application
/// Support). Never leaves the device.
@MainActor
@Observable
final class PersonalRatingsStore {
    private(set) var ratings = PersonalRatings()
    private(set) var lastError: String?

    private let fileStore: PersonalRatingsFileStore?

    /// Pass `nil` for an in-memory store (previews).
    init(fileStore: PersonalRatingsFileStore? = try? PersonalRatingsFileStore.applicationSupport()) {
        self.fileStore = fileStore
        guard let fileStore else { return }
        do {
            ratings = try fileStore.load()
        } catch {
            // Fail soft: keep the unreadable file as a backup (never overwrite
            // it silently), then start with no ratings.
            let backup = CorruptFileQuarantine.quarantine(fileStore.fileURL)
            lastError = backup == nil
                ? "Your saved ratings couldn't be read, so they were reset."
                : "Your saved ratings couldn't be read. A backup was kept and ratings were reset."
        }
    }

    func rating(for movieId: String) -> Int? { ratings.rating(for: movieId) }
    func status(for movieId: String) -> WatchStatus? { ratings.status(for: movieId) }
    func entry(for movieId: String) -> PersonalMovieEntry? { ratings.entry(for: movieId) }

    func halfStars(for movieId: String) -> Int? { ratings.halfStars(for: movieId) }

    func setHalfStars(_ halfStars: Int?, for movieId: String) {
        ratings.setHalfStars(halfStars, for: movieId)
        persist()
    }

    func setRating(_ stars: Int?, for movieId: String) {
        ratings.setRating(stars, for: movieId)
        persist()
    }

    func setStatus(_ status: WatchStatus?, for movieId: String) {
        ratings.setStatus(status, for: movieId)
        persist()
    }

    private func persist() {
        guard let fileStore else { return }
        do {
            try fileStore.save(ratings)
            lastError = nil
        } catch {
            lastError = "Couldn’t save your ratings: \(error.localizedDescription)"
        }
    }
}
