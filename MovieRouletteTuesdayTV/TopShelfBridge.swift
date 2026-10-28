import Foundation
import MRTCore
#if canImport(TVServices)
import TVServices
#endif

/// Writes the latest episode into the App Group and asks tvOS to reload Top Shelf.
/// The extension reads that snapshot, draws the banner, and opens
/// `mrt://episode/<guid>` on select. No App Group (signing team not chosen yet)
/// means this does nothing and the static Top Shelf image stays up.
enum TopShelfBridge {
    static func publish(episodes: [PodcastEpisode], catalog: MovieCatalog?, showArtwork: URL?) {
        guard !ProcessInfo.processInfo.arguments.contains("-MRTUITest") else { return }
        guard let episode = TopShelfEpisodeBuilder.make(
            episodes: episodes,
            catalog: catalog,
            showArtwork: showArtwork,
            showName: catalog?.showInfo.name
        ) else { return }
        guard let store = TopShelfSnapshotStore.appGroup() else { return }
        do {
            if try store.saveIfChanged(TopShelfSnapshot(episode: episode, updatedAt: Date())) {
                reload()
            }
        } catch {
            // Shelf data is best-effort; a failed write must not affect the app.
        }
    }

    private static func reload() {
        #if canImport(TVServices)
        TVTopShelfContentProvider.topShelfContentDidChange()
        #endif
    }
}
