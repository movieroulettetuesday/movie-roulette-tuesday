import Foundation

/// Very occasional surprises layered on top of a normal spin.
public enum RareOutcome: String, Equatable, Sendable {
    /// Ordinary spin: the landed category picks the movie.
    case normal
    /// "Re-spin forced!": show a brief message, then spin again automatically.
    case forcedRespin
    /// "Infamous jackpot": the result is a catalog movie picked by
    /// `InfamousSelection` (lower listener ratings more likely), with special styling.
    case infamousJackpot
}

/// Odds for rare outcomes. Pure value; the decision is a function of a uniform
/// value (or an injected RNG), so it is fully deterministic in tests.
public struct RareOutcomePolicy: Equatable, Sendable {
    public var isEnabled: Bool
    public var forcedRespinChance: Double
    public var infamousJackpotChance: Double

    public init(isEnabled: Bool = true, forcedRespinChance: Double = 0.01, infamousJackpotChance: Double = 0.01) {
        self.isEnabled = isEnabled
        self.forcedRespinChance = Self.clampChance(forcedRespinChance)
        // Both bands share [0, 1); never let them overflow it.
        self.infamousJackpotChance = min(Self.clampChance(infamousJackpotChance), 1 - self.forcedRespinChance)
    }

    public static let `default` = RareOutcomePolicy()
    public static let disabled = RareOutcomePolicy(isEnabled: false)

    private static func clampChance(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
    }
}

public enum RareOutcomeRoller {
    /// Decide from a uniform `unitValue` in `[0, 1)`:
    /// `[0, respin)` -> forced re-spin, `[respin, respin + jackpot)` -> jackpot,
    /// everything else -> normal.
    ///
    /// - `allowRespin`: false for a spin that was itself forced, so re-spins never chain.
    /// - `infamousAvailable`: false when there is nothing to pick for a jackpot
    ///   (see `jackpotCandidates(in:)`); the jackpot band then falls back to a normal spin.
    public static func outcome(
        unitValue: Double,
        policy: RareOutcomePolicy,
        infamousAvailable: Bool,
        allowRespin: Bool = true
    ) -> RareOutcome {
        guard policy.isEnabled, unitValue.isFinite else { return .normal }
        let unit = min(max(unitValue, 0), 1)
        if unit < policy.forcedRespinChance {
            return allowRespin ? .forcedRespin : .normal
        }
        if unit < policy.forcedRespinChance + policy.infamousJackpotChance {
            return infamousAvailable ? .infamousJackpot : .normal
        }
        return .normal
    }

    /// Same as above, drawing the uniform value from `rng`. Always consumes
    /// exactly one value, so the rest of the random stream doesn't depend on settings.
    public static func roll<G: RandomNumberGenerator>(
        policy: RareOutcomePolicy,
        infamousAvailable: Bool,
        allowRespin: Bool = true,
        using rng: inout G
    ) -> RareOutcome {
        let unit = Double.random(in: 0..<1, using: &rng)
        return outcome(unitValue: unit, policy: policy, infamousAvailable: infamousAvailable, allowRespin: allowRespin)
    }

    /// Everything a jackpot can land on: every catalog movie (the jackpot has
    /// never been limited by category).
    public static func jackpotCandidates(in catalog: MovieCatalog) -> [Movie] {
        catalog.movies
    }

    /// Jackpot resolution: a movie chosen by `InfamousSelection` (weighted by
    /// `listenerAverages`, movie id -> average stars) plus the category to show
    /// it under (the landed one if the movie belongs to it, otherwise the
    /// movie's first known category, otherwise the landed one).
    /// Consumes exactly one RNG value when the catalog has movies.
    public static func jackpotPick<G: RandomNumberGenerator>(
        in catalog: MovieCatalog,
        landed: RouletteCategory,
        listenerAverages: [String: Double] = [:],
        using rng: inout G
    ) -> (movie: Movie, category: RouletteCategory)? {
        guard let movie = InfamousSelection.pick(
            from: jackpotCandidates(in: catalog), averages: listenerAverages, using: &rng
        ) else { return nil }
        if movie.categories.contains(landed.id) || landed.movieIds.contains(movie.id) {
            return (movie, landed)
        }
        let category = movie.categories.lazy.compactMap(catalog.category(withId:)).first ?? landed
        return (movie, category)
    }
}

/// 1.0.1: which movie the "Infamous jackpot" lands on. A random catalog movie,
/// weighted by its average listener rating so worse-rated movies come up more:
///
///     rated (avg clamped to 0.5...5):  weight = 5.5 - avg   (0.5 ... 5.0)
///     unrated (no / invalid average):  weight = 5.5 - 3.0 = 2.5
///
/// There are no per-movie flags: a legacy `isInfamous` catalog key is ignored.
///
///     P(movie) = weight / sum(weights)
///
/// Pure and deterministic for a given RNG; draws exactly one uniform value.
public enum InfamousSelection {
    /// Top of the listener scale (stars).
    public static let maxStars = 5.0
    /// Bottom of the listener scale: one half-star.
    public static let minStars = 0.5
    /// Unrated movies weigh like a movie averaging this many stars.
    public static let unratedStars = 3.0

    /// Weight for an average of `stars` (clamped to `minStars...maxStars`;
    /// a non-finite value counts as unrated).
    public static func weight(forAverageStars stars: Double) -> Double {
        let clamped = stars.isFinite ? min(max(stars, minStars), maxStars) : unratedStars
        return (maxStars + 0.5) - clamped
    }

    /// 2.5: the weight of a 3-star average.
    public static var unratedWeight: Double { weight(forAverageStars: unratedStars) }
    /// 5.0: the weight of the lowest possible (half-star) average (the maximum weight).
    public static var maxWeight: Double { weight(forAverageStars: minStars) }

    /// Always > 0 and finite.
    public static func weight(averageStars: Double?) -> Double {
        guard let averageStars, averageStars.isFinite else { return unratedWeight }
        return weight(forAverageStars: averageStars)
    }

    public static func weight(for movie: Movie, averages: [String: Double]) -> Double {
        weight(averageStars: averages[movie.id])
    }

    public static func weights(for movies: [Movie], averages: [String: Double]) -> [Double] {
        movies.map { weight(for: $0, averages: averages) }
    }

    /// Selection probability of each movie (same order); empty in -> empty out.
    public static func probabilities(for movies: [Movie], averages: [String: Double]) -> [Double] {
        let w = weights(for: movies, averages: averages)
        let total = w.reduce(0, +)
        return total > 0 ? w.map { $0 / total } : []
    }

    /// Index chosen by a uniform `unitValue` in `[0, 1)`; nil only when `movies` is empty.
    public static func pickIndex(for movies: [Movie], averages: [String: Double], unitValue: Double) -> Int? {
        MovieSelector.pickIndex(weights: weights(for: movies, averages: averages), unitValue: unitValue)
    }

    /// Weighted random movie; nil only when `movies` is empty. Draws exactly
    /// one `Double.random(in: 0..<1, using:)` value.
    public static func pick<G: RandomNumberGenerator>(
        from movies: [Movie],
        averages: [String: Double],
        using rng: inout G
    ) -> Movie? {
        guard !movies.isEmpty else { return nil }
        let unit = Double.random(in: 0..<1, using: &rng)
        guard let index = pickIndex(for: movies, averages: averages, unitValue: unit) else { return nil }
        return movies[index]
    }
}
