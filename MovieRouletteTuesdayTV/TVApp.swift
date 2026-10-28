import SwiftUI
import MRTCore
import MRTShared

/// Apple TV app. Roulette, Episodes, Movies, and Stats share MRTKit with iOS.
///
/// History and personal ratings live in UserDefaults (the last 100 spins, no
/// archive, no iCloud). tvOS may purge Application Support; the caches can refetch.
/// Appearance follows the system Light/Dark setting.
///
/// Top Shelf (latest episode) is not in this target. It needs its own extension,
/// `com.movieroulettetuesday.app.topshelf`, plus the layered icon and Top Shelf
/// art. Deep links (`mrt://movie/…`, `mrt://episode/…`) are already handled.
///
/// Siri: App Intents exist on tvOS, but the iOS spin intent records
/// `SpinHistoryStore.shared` (the iPhone file, with an archive). A TV shortcut
/// would have to record into this UserDefaults log or Stats would miss it.
/// Whether the Siri Remote runs third-party shortcuts still needs a check on
/// a real Apple TV, so the intent is not in the TV target.
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
        }
        let history = SpinHistoryStore(
            fileStore: nil,
            detailLimit: SpinHistoryStore.tvDetailLimit,
            defaults: .standard,
            keepsArchive: false
        )
        let community = CommunityService.makeDefault()
        _community = State(initialValue: community)
        _personal = State(initialValue: PersonalRatingsStore(fileStore: nil, defaults: .standard))
        _episodes = State(initialValue: EpisodeStore())
        _roulette = State(initialValue: RouletteViewModel(
            catalogSource: AppCatalog.localSource(),
            catalogRefresher: AppCatalog.refresher(),
            history: history,
            sideEffects: .none,
            listenerAverages: { [weak community] in community?.listenerAverages ?? [:] }
        ))
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
