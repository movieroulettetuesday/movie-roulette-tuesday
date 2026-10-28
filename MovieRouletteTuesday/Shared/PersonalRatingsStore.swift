import Foundation
import Observation
import MRTCore
import MRTShared

/// Observable wrapper around the local personal-ratings JSON (Application
/// Support). Never leaves the device.
@MainActor
@Observable
final class PersonalRatingsStore {
    /// UserDefaults key for ratings on Apple TV. Not used by iOS.
    static let tvDefaultsKey = "tv.personalRatings"

    private(set) var ratings = PersonalRatings()
    private(set) var lastError: String?

    private let fileStore: PersonalRatingsFileStore?
    /// When set, ratings are JSON in UserDefaults (Apple TV). `fileStore` is ignored.
    private let defaults: UserDefaults?
    private let defaultsKey: String

    /// Pass `fileStore: nil` for an in-memory store (previews).
    /// Pass `defaults` for Apple TV, where Application Support can be purged.
    init(
        fileStore: PersonalRatingsFileStore? = try? PersonalRatingsFileStore.applicationSupport(),
        defaults: UserDefaults? = nil,
        defaultsKey: String = PersonalRatingsStore.tvDefaultsKey
    ) {
        self.fileStore = defaults == nil ? fileStore : nil
        self.defaults = defaults
        self.defaultsKey = defaultsKey
        if let defaults {
            if let data = defaults.data(forKey: defaultsKey) {
                do {
                    ratings = try JSONDecoder().decode(PersonalRatings.self, from: data)
                } catch {
                    defaults.removeObject(forKey: defaultsKey)
                    lastError = "Your saved ratings couldn't be read, so they were reset."
                }
            }
            return
        }
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
        if let defaults {
            do {
                defaults.set(try JSONEncoder().encode(ratings), forKey: defaultsKey)
                lastError = nil
            } catch {
                lastError = "Couldn’t save your ratings: \(error.localizedDescription)"
            }
            return
        }
        guard let fileStore else { return }
        do {
            try fileStore.save(ratings)
            lastError = nil
        } catch {
            lastError = "Couldn’t save your ratings: \(error.localizedDescription)"
        }
    }
}
