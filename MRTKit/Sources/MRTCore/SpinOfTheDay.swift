import Foundation

/// Deterministic "Spin of the Day": the same date always gives the same
/// category and movie, in the app and in the widget, with no shared state.
public enum SpinOfTheDay {
    public struct Pick: Equatable, Sendable {
        public let movie: Movie
        public let category: RouletteCategory?
        public let dayKey: String
    }

    /// "2026-10-08" in the given calendar's time zone.
    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// FNV-1a 64-bit. Swift's `Hasher` is seeded per process, so it can't be used here.
    public static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    /// Picks a wheel category for the day, then a movie from it. Falls back to
    /// the whole catalog if that category has no usable movies.
    public static func pick(for date: Date, in catalog: MovieCatalog, calendar: Calendar = .current) -> Pick? {
        let key = dayKey(for: date, calendar: calendar)
        let selector = MovieSelector()

        if !catalog.categories.isEmpty {
            let category = catalog.categories[Int(stableHash("category:" + key) % UInt64(catalog.categories.count))]
            let candidates = selector.candidates(for: category, in: catalog)
            if !candidates.isEmpty {
                let movie = candidates[Int(stableHash("movie:\(key):\(category.id)") % UInt64(candidates.count))]
                return Pick(movie: movie, category: category, dayKey: key)
            }
        }
        guard !catalog.movies.isEmpty else { return nil }
        let movie = catalog.movies[Int(stableHash("movie:" + key) % UInt64(catalog.movies.count))]
        let category = movie.categories.first.flatMap(catalog.category(withId:))
        return Pick(movie: movie, category: category, dayKey: key)
    }

    /// Start of the next day, for the widget's timeline refresh.
    public static func nextRefresh(after date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
            ?? date.addingTimeInterval(6 * 60 * 60)
    }
}
