import SwiftUI
import MRTCore
import MRTShared

/// Apple TV app. Roulette, Episodes, Movies, and Stats share MRTKit with iOS.
///
/// History and personal ratings live in UserDefaults (the last 100 spins, no
/// archive, no iCloud). tvOS may purge Application Support; the caches can refetch.
/// Appearance follows the system Light/Dark setting.
///
/// Top Shelf (latest episode) is the `MovieRouletteTuesdayTopShelf` extension,
/// bundle id `com.movieroulettetuesday.app.topshelf`. This target writes the
/// episode into the App Group; the extension draws the banner and selects
/// `mrt://episode/<guid>`. Static shelf art in the asset catalog is the
/// fallback until that snapshot exists. Deep links are handled in `TVRootView`.
///
/// Siri App Intents live in this target (not MRTKit: Top Shelf is an
/// extension and cannot compile ForegroundContinuableIntent). Spin records
/// into the same UserDefaults history the wheel uses, then opens the app
/// and plays that result. On-device “What should I watch?” is compiled
/// out (Foundation Models is tvOS-unavailable in the 27.2 SDK) and the
/// intent offers Spin. Invocation on a real Apple TV is still unproven.
@main
struct MovieRouletteTuesdayTVApp: App {
    @State private var roulette: RouletteViewModel
    @State private var episodes: EpisodeStore
    @State private var personal: PersonalRatingsStore
    @State private var community: CommunityService

    init() {
        // UI tests share the simulator's UserDefaults. A spin from an earlier
        // test would otherwise show up as "Last landed on" after a cancelled spin.
        if ProcessInfo.processInfo.arguments.contains("-MRTUITest") {
            UserDefaults.standard.removeObject(forKey: SpinHistoryStore.tvDefaultsKey)
            UserDefaults.standard.removeObject(forKey: PersonalRatingsStore.tvDefaultsKey)
            Self.seedUITestRatingIfRequested()
        }
        let history = SpinHistoryStore(
            fileStore: nil,
            detailLimit: SpinHistoryStore.tvDetailLimit,
            defaults: .standard,
            keepsArchive: false
        )
        let community = CommunityService.makeDefault()
        _community = State(initialValue: community)
        _personal = State(initialValue: PersonalRatingsStore.shared)
        _episodes = State(initialValue: EpisodeStore())
        _roulette = State(initialValue: RouletteViewModel(
            catalogSource: AppCatalog.localSource(),
            catalogRefresher: AppCatalog.refresher(),
            history: history,
            sideEffects: .none,
            listenerAverages: { [weak community] in community?.listenerAverages ?? [:] }
        ))
        // Intents must write the same UserDefaults history and ratings the UI shows.
        IntentRuntime.history = { history }
        IntentRuntime.ratings = { PersonalRatingsStore.shared }
    }

    /// `-MRTSeedRating <movieId> <halfStars>` after the UI-test wipe.
    /// Half-stars are 1...10. Zero and null are not written.
    private static func seedUITestRatingIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-MRTSeedRating"),
              args.indices.contains(index + 2),
              let half = Int(args[index + 2]),
              HalfStars.clamped(half) != nil else { return }
        var ratings = PersonalRatings()
        let movieId = args[index + 1]
        ratings.setHalfStars(half, for: movieId, now: Date(timeIntervalSinceReferenceDate: 0))
        if let watch = args.firstIndex(of: "-MRTSeedWatchlist"), args.indices.contains(watch + 1) {
            ratings.setStatus(.wantToWatch, for: args[watch + 1], now: Date(timeIntervalSinceReferenceDate: 1))
        }
        guard let data = try? JSONEncoder().encode(ratings) else { return }
        UserDefaults.standard.set(data, forKey: PersonalRatingsStore.tvDefaultsKey)
    }

    var body: some Scene {
        WindowGroup {
            TVRootView(roulette: roulette, episodes: episodes)
                .environment(personal)
                .environment(community)
                .environment(roulette.history)
        }
    }
}
