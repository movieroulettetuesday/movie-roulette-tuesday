import Foundation

/// Tunables for weighted movie selection.
public struct SelectionPolicy: Equatable, Sendable {
    /// How many of the most recent spins (across all categories) count as "recent".
    public var recentWindow: Int
    /// Weight multiplier for the movie from the very last spin. Movies further
    /// back in the window recover linearly toward 1.
    public var mostRecentMultiplier: Double

    public init(recentWindow: Int = 5, mostRecentMultiplier: Double = 0.1) {
        self.recentWindow = max(0, recentWindow)
        self.mostRecentMultiplier = min(max(mostRecentMultiplier, 0), 1)
    }

    public static let `default` = SelectionPolicy()
}

/// Resolves a category to a movie with weighted randomness. Pure value type;
/// all randomness comes from the injected generator, so tests are deterministic.
public struct MovieSelector: Sendable {
    public var policy: SelectionPolicy

    public init(policy: SelectionPolicy = .default) {
        self.policy = policy
    }

    /// Movies eligible for a category: the category's `movieIds` (in order)
    /// plus any movie that lists the category itself, de-duplicated. Unknown
    /// ids are ignored.
    public func candidates(for category: RouletteCategory, in catalog: MovieCatalog) -> [Movie] {
        var seen = Set<String>()
        var result: [Movie] = []
        for id in category.movieIds {
            if let movie = catalog.movie(withId: id), seen.insert(id).inserted {
                result.append(movie)
            }
        }
        for movie in catalog.movies where movie.categories.contains(category.id) {
            if seen.insert(movie.id).inserted {
                result.append(movie)
            }
        }
        return result
    }

    /// Recency multiplier for a movie last spun `spinsAgo` spins ago
    /// (1 = the most recent spin). `nil` or outside the window -> 1.
    public func recencyMultiplier(spinsAgo: Int?) -> Double {
        guard let spinsAgo, spinsAgo >= 1, spinsAgo <= policy.recentWindow else { return 1 }
        let recovered = Double(spinsAgo - 1) / Double(policy.recentWindow)
        return policy.mostRecentMultiplier + (1 - policy.mostRecentMultiplier) * recovered
    }

    /// Relative selection weight for a movie given chronological history (oldest first).
    public func weight(for movie: Movie, history: [SpinResult]) -> Double {
        let recent = history.suffix(policy.recentWindow).reversed()
        let spinsAgo = recent.firstIndex(where: { $0.movieId == movie.id })
            .map { recent.distance(from: recent.startIndex, to: $0) + 1 }
        return recencyMultiplier(spinsAgo: spinsAgo)
    }

    public func weightedCandidates(
        for category: RouletteCategory,
        in catalog: MovieCatalog,
        history: [SpinResult]
    ) -> [(movie: Movie, weight: Double)] {
        candidates(for: category, in: catalog).map { ($0, weight(for: $0, history: history)) }
    }

    /// Picks a movie from `category`, or `nil` if the category has no movies.
    public func selectMovie<G: RandomNumberGenerator>(
        from category: RouletteCategory,
        in catalog: MovieCatalog,
        history: [SpinResult],
        using rng: inout G
    ) -> Movie? {
        let weighted = weightedCandidates(for: category, in: catalog, history: history)
        let unit = Double.random(in: 0..<1, using: &rng)
        guard let index = Self.pickIndex(weights: weighted.map(\.weight), unitValue: unit) else { return nil }
        return weighted[index].movie
    }

    /// Weighted pick from a uniform value in `[0, 1)`: index `i` owns the
    /// interval `[sum(w[..<i]), sum(w[...i]))` scaled to the total. Zero,
    /// negative or non-finite weights never win (unless every weight is
    /// unusable, in which case the pick is uniform). Empty input -> `nil`.
    public static func pickIndex(weights: [Double], unitValue: Double) -> Int? {
        guard !weights.isEmpty else { return nil }
        let unit = unitValue.isFinite ? min(max(unitValue, 0), 1) : 0
        let usable = weights.map { $0.isFinite && $0 > 0 ? $0 : 0 }
        let total = usable.reduce(0, +)
        guard total > 0 else {
            return min(Int(unit * Double(weights.count)), weights.count - 1)
        }
        let target = unit * total
        var cumulative = 0.0
        for (index, weight) in usable.enumerated() where weight > 0 {
            cumulative += weight
            if target < cumulative { return index }
        }
        // unit == 1 or floating-point slack: last index that can win.
        return usable.lastIndex(where: { $0 > 0 })
    }
}
