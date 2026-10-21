import SwiftUI
import MRTCore
import MRTShared

/// Apple TV app, phase 1: the Roulette tab (wheel, Spin, result) on the shared
/// MRTKit code. Episodes, Movies and Stats are placeholders until their mockups
/// are approved.
@main
struct MovieRouletteTuesdayTVApp: App {
    @State private var roulette: RouletteViewModel

    init() {
        // Spin history stays in memory on TV for now: tvOS can purge local files,
        // and where TV history should live (UserDefaults cap vs iCloud) is still
        // an open decision (plan §3a). No widget on tvOS, so no side effects.
        _roulette = State(initialValue: RouletteViewModel(
            catalogSource: AppCatalog.localSource(),
            catalogRefresher: AppCatalog.refresher(),
            history: SpinHistoryStore(fileStore: nil),
            sideEffects: .none
        ))
    }

    var body: some Scene {
        WindowGroup {
            TVRootView(roulette: roulette)
                .preferredColorScheme(.dark)
        }
    }
}
