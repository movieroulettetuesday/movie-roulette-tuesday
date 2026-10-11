import BackgroundTasks
import Foundation
import UIKit
import UserNotifications

/// Optional "New-episode alert" (Settings > New Episodes, off by default).
///
/// A `BGAppRefreshTask` fetches the show's public RSS feed (the same request the
/// Episodes tab makes) and posts a local notification for episodes newer than
/// the last ones seen. No server, no account, no push token: everything stays
/// on the device. iOS decides when the refresh actually runs.
enum NewEpisodeAlerts {
    static let taskIdentifier = "com.movieroulettetuesday.app.new-episode-check"
    static let enabledKey = "settings.newEpisodeAlerts"
    static let watermarkKey = "newEpisodeAlerts.watermark"
    /// Earliest next check; iOS usually runs it later.
    static let refreshInterval: TimeInterval = 6 * 60 * 60
    static let guidUserInfoKey = "episodeGUID"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    // MARK: Watermark

    static func loadWatermark(_ defaults: UserDefaults = .standard) -> NewEpisodeWatermark? {
        guard let data = defaults.data(forKey: watermarkKey) else { return nil }
        return try? JSONDecoder().decode(NewEpisodeWatermark.self, from: data)
    }

    static func saveWatermark(_ mark: NewEpisodeWatermark, _ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(mark) { defaults.set(data, forKey: watermarkKey) }
    }

    /// Forget the marker; the next check only sets a new baseline (no alert).
    static func resetWatermark(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: watermarkKey)
    }

    /// Episodes the user can already see in the app never alert later.
    static func markSeen(_ episodes: [PodcastEpisode]) {
        guard !episodes.isEmpty else { return }
        var mark = NewEpisodeDiff.watermark(for: episodes)
        if let old = loadWatermark() {
            if let oldDate = old.latestDate, let newDate = mark.latestDate, oldDate > newDate { mark.latestDate = oldDate }
            mark.seenGUIDs = Array((mark.seenGUIDs + old.seenGUIDs.filter { !mark.seenGUIDs.contains($0) })
                .prefix(NewEpisodeWatermark.guidLimit))
        }
        saveWatermark(mark)
    }

    // MARK: Permission

    /// Asked only when the user turns the toggle on. Returns whether alerts can be shown.
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        case .notDetermined:
            // Alerts + sound only: the app never sets a badge.
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        @unknown default: return false
        }
    }

    // MARK: Background refresh

    // Registration: `.backgroundTask(.appRefresh(taskIdentifier))` on the
    // WindowGroup scene (MovieRouletteTuesdayApp) registers the handler.

    static func scheduleIfEnabled() {
        guard isEnabled else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: refreshInterval)
        try? BGTaskScheduler.shared.submit(request) // fails harmlessly in the simulator
    }

    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    }

    /// Fetch the feed, diff against the watermark, notify. Returns success.
    @discardableResult
    static func checkNow() async -> Bool {
        guard isEnabled else { return true }
        do {
            let feed = try await EpisodeFeedIO.fetchRemote()
            let episodes = feed.episodes
            let mark = loadWatermark()
            let new = NewEpisodeDiff.newEpisodes(in: episodes, since: mark)
            if mark == nil || !new.isEmpty { markSeen(episodes) }
            if let text = NewEpisodeDiff.notificationText(for: new), let newest = new.first {
                let content = UNMutableNotificationContent()
                content.title = text.title
                content.body = text.body
                content.sound = .default
                content.userInfo = [guidUserInfoKey: newest.guid]
                content.threadIdentifier = "new-episodes"
                let request = UNNotificationRequest(identifier: "episode-\(newest.guid)", content: content, trigger: nil)
                try await UNUserNotificationCenter.current().add(request)
            }
            return true
        } catch {
            return false
        }
    }
}

/// Routes a tapped new-episode notification to that episode's page.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = NotificationRouter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let guid = response.notification.request.content.userInfo[NewEpisodeAlerts.guidUserInfoKey] as? String
        guard let guid else { return }
        await MainActor.run { AppRouter.shared.open(.episode(guid: guid)) }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
