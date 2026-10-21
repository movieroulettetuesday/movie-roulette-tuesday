import Foundation

/// Very occasional surprises layered on top of a normal spin.
public enum RareOutcome: String, Equatable, Sendable {
    /// Ordinary spin: the landed category picks the movie.
    case normal
    /// "Re-spin forced!": show a brief message, then spin again automatically.
    case forcedRespin
    /// "Infamous jackpot": the result is an `isInfamous` movie, with special styling.
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
    /// - `infamousAvailable`: false when the catalog has no infamous movies; the
    ///   jackpot band then falls back to a normal spin.
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

    public static func infamousMovies(in catalog: MovieCatalog) -> [Movie] {
        catalog.movies.filter(\.isInfamous)
    }

    /// Jackpot resolution: a uniformly chosen infamous movie plus the category
    /// to show it under (the landed one if the movie belongs to it, otherwise
    /// the movie's first known category, otherwise the landed one).
    public static func jackpotPick<G: RandomNumberGenerator>(
        in catalog: MovieCatalog,
        landed: RouletteCategory,
        using rng: inout G
    ) -> (movie: Movie, category: RouletteCategory)? {
        let infamous = infamousMovies(in: catalog)
        guard !infamous.isEmpty else { return nil }
        let movie = infamous[Int.random(in: 0..<infamous.count, using: &rng)]
        if movie.categories.contains(landed.id) || landed.movieIds.contains(movie.id) {
            return (movie, landed)
        }
        let category = movie.categories.lazy.compactMap(catalog.category(withId:)).first ?? landed
        return (movie, category)
    }
}
