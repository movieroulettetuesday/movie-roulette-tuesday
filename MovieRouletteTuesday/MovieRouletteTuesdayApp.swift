import SwiftUI
import UIKit
import UserNotifications

@main
struct MovieRouletteTuesdayApp: App {
    @State private var episodes = EpisodeStore()
    @State private var roulette: RouletteViewModel
    @State private var personal = PersonalRatingsStore()
    @State private var community = CommunityService.makeDefault()
    /// Cold-launch opening: created once per process, so it never replays when
    /// the app returns from the background.
    @State private var splash: SplashState

    init() {
        let history = SpinHistoryStore.shared
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        _episodes = State(initialValue: EpisodeStore())
        _roulette = State(initialValue: RouletteViewModel(
            catalogSource: AppCatalog.localSource(),
            catalogRefresher: AppCatalog.refresher(),
            history: history
        ))
        #if DEBUG
        _splash = State(initialValue: SplashState(
            enabled: !DebugLaunch.noSplash,
            reduceMotion: DebugLaunch.splashReduceMotion ? true : nil
        ))
        #else
        _splash = State(initialValue: SplashState())
        #endif
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView(roulette: roulette, episodes: episodes)
                    .environment(personal)
                    .environment(community)
                    .environment(splash)
                    .environment(roulette.history)
                // Pure overlay: ContentView (and its data loading) runs underneath from the first frame.
                if splash.isActive {
                    SplashCover(state: splash)
                        .zIndex(1)
                }
            }
            .appAppearance()
            .task {
                splash.captureLaunchScheme(
                    from: UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
                #if DEBUG
                await splash.play(hold: DebugLaunch.splashHold)
                #else
                await splash.play()
                #endif
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { NewEpisodeAlerts.scheduleIfEnabled() }
        }
        // New-episode alert (opt-in): iOS wakes the app now and then to check the RSS feed.
        .backgroundTask(.appRefresh(NewEpisodeAlerts.taskIdentifier)) {
            await NewEpisodeAlerts.checkNow()
            NewEpisodeAlerts.scheduleIfEnabled()
        }
    }
}
