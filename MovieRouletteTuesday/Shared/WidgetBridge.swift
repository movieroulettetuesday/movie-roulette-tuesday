import Foundation
import WidgetKit
import MRTCore

/// Pushes the latest episode and last spin to the App Group so the home-screen
/// widget can show them. If the App Group isn't available (for example, no
/// signing team selected yet) this does nothing, and the widget shows only
/// Spin of the Day.
enum WidgetBridge {
    static func publishLatestEpisode(from episodes: [PodcastEpisode]) {
        guard let latest = WidgetSnapshot.latest(in: episodes) else { return }
        update { $0.latestEpisode = WidgetSnapshot.EpisodeInfo(episode: latest) }
    }

    static func publishSpin(movie: Movie, category: RouletteCategory, at date: Date) {
        update {
            $0.lastSpin = WidgetSnapshot.SpinInfo(
                movieId: movie.id,
                title: movie.title,
                year: movie.year,
                categoryName: category.displayName,
                colorHex: category.displayHex,
                timestamp: date
            )
        }
    }

    /// A refreshed movie list was cached in the App Group; let the widget re-read it.
    static func catalogUpdated() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func update(_ mutate: (inout WidgetSnapshot) -> Void) {
        guard let store = WidgetSnapshotStore.appGroup() else { return }
        do {
            if try store.update(mutate) {
                WidgetCenter.shared.reloadAllTimelines()
            }
        } catch {
            // Widget data is best-effort; never let it affect the app.
        }
    }
}
