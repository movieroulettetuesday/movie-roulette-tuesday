import Foundation

/// A complete spin without the animation, for Siri / Shortcuts. Uses exactly
/// the wheel's primitives: a random target angle on the same `WheelGeometry`,
/// `segmentIndex(forRotation:)`, the rare-outcome roller and `MovieSelector`.
/// A forced re-spin is resolved immediately by spinning once more (re-spins
/// never chain, as in the app).
public enum QuickSpin {
    public struct Outcome: Equatable, Sendable {
        public let movie: Movie
        /// The category credited for the spin (the jackpot's category on a jackpot).
        public let category: RouletteCategory
        /// Where the wheel landed.
        public let landed: RouletteCategory
        public let isJackpot: Bool
        public let wasForcedRespin: Bool
    }

    public static func resolve<G: RandomNumberGenerator>(
        catalog: MovieCatalog,
        history: [SpinResult],
        rareOutcomes: RareOutcomePolicy,
        selector: MovieSelector = MovieSelector(),
        listenerAverages: [String: Double] = [:],
        using rng: inout G
    ) -> Outcome? {
        guard !catalog.categories.isEmpty else { return nil }
        let geometry = WheelGeometry(categories: catalog.categories)
        var forced = false
        for attempt in 0..<2 {
            let angle = geometry.randomTargetRotation(from: 0, fullTurns: 1...1, using: &rng)
            let index = geometry.segmentIndex(forRotation: angle)
            guard catalog.categories.indices.contains(index) else { return nil }
            let landed = catalog.categories[index]
            let outcome = RareOutcomeRoller.roll(
                policy: rareOutcomes,
                infamousAvailable: !RareOutcomeRoller.jackpotCandidates(in: catalog).isEmpty,
                allowRespin: attempt == 0,
                using: &rng
            )
            if outcome == .forcedRespin { forced = true; continue }
            if outcome == .infamousJackpot,
               let pick = RareOutcomeRoller.jackpotPick(in: catalog, landed: landed, listenerAverages: listenerAverages, using: &rng) {
                return Outcome(movie: pick.movie, category: pick.category, landed: landed, isJackpot: true, wasForcedRespin: forced)
            }
            guard let movie = selector.selectMovie(from: landed, in: catalog, history: history, using: &rng) else { return nil }
            return Outcome(movie: movie, category: landed, landed: landed, isJackpot: false, wasForcedRespin: forced)
        }
        return nil
    }
}
