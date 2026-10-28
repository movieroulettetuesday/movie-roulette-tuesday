import TVServices
import UIKit
import MRTCore

/// Top Shelf extension principal class (`com.apple.tv-top-shelf`).
///
/// Publishes the latest episode. Select opens `mrt://episode/<guid>`, which
/// `TVRootView.open` routes to the episode page. A rendered 1920×720 banner
/// uses the inset style (the approved full-width layout). If that file can't
/// be written, one sectioned item still carries the title and artwork URL.
/// No snapshot and no feed: return nil so the static Top Shelf image shows.
final class TopShelfContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        Task { @MainActor in
            let content = await TopShelfExtensionContent.load()
            completionHandler(content)
        }
    }
}

@MainActor
enum TopShelfExtensionContent {
    static func load() async -> TVTopShelfContent? {
        let store = TopShelfSnapshotStore.appGroup()
        let cached = store?.load()
        var snapshot = cached
        var episodeChanged = false
        if TopShelfLoadPlan.decide(snapshot: cached, now: Date()) == .refresh {
            if let fresh = await refreshFromFeed() {
                episodeChanged = cached?.episode != fresh.episode
                snapshot = fresh
                try? store?.save(fresh)
            }
        }
        guard let snapshot else { return nil }
        let episode = snapshot.episode
        guard let store else {
            return make(TopShelfContentPlan.make(episode: episode, banner1x: nil, banner2x: nil))
        }

        let bannersReady = store.bannerURL(scale: 1, matching: episode.guid) != nil
        let waitingOnArt = store.isArtworkPending() && episode.imageURL != nil
        if bannersReady, !episodeChanged, !waitingOnArt {
            return make(plan(for: episode, store: store))
        }

        let image = await artwork(at: episode.imageURL)
        let png1 = TopShelfBannerRenderer.png(episode: episode, artwork: image, canvas: TopShelf.insetSize1x)
        let png2 = TopShelfBannerRenderer.png(episode: episode, artwork: image, canvas: TopShelf.insetSize2x)
        if let png1, let png2 {
            try? store.writeBanners(scale1: png1, scale2: png2, guid: episode.guid)
            try? store.setArtworkPending(image == nil && episode.imageURL != nil)
        }
        return make(plan(for: episode, store: store))
    }

    private static func plan(for episode: TopShelfEpisode, store: TopShelfSnapshotStore) -> TopShelfItemModel {
        TopShelfContentPlan.make(
            episode: episode,
            banner1x: store.bannerURL(scale: 1, matching: episode.guid),
            banner2x: store.bannerURL(scale: 2, matching: episode.guid)
        )
    }

    private static func refreshFromFeed() async -> TopShelfSnapshot? {
        do {
            let feed = try EpisodeFeedIO.validated(await EpisodeFeedIO.fetchRemote())
            guard let episode = TopShelfEpisodeBuilder.make(
                episodes: feed.episodes,
                showArtwork: feed.artworkURL,
                showName: feed.title,
                now: Date()
            ) else { return nil }
            return TopShelfSnapshot(episode: episode, updatedAt: Date())
        } catch {
            return nil
        }
    }

    private static func artwork(at url: URL?) async -> UIImage? {
        guard let url, let data = await artworkData(at: url) else { return nil }
        return UIImage(data: data)
    }

    private static func artworkData(at url: URL) async -> Data? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = TopShelf.artworkFetchTimeout
        configuration.timeoutIntervalForResource = TopShelf.artworkFetchTimeout
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: TopShelf.artworkFetchTimeout)
        request.timeoutInterval = TopShelf.artworkFetchTimeout
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  !data.isEmpty, data.count <= 15 << 20 else { return nil }
            return data
        } catch {
            return nil
        }
    }

    static func make(_ plan: TopShelfItemModel) -> TVTopShelfContent {
        switch plan.style {
        case .inset:
            let item = TVTopShelfItem(identifier: plan.guid)
            item.displayAction = TVTopShelfAction(url: plan.deepLink)
            applyImages(plan, to: item)
            return TVTopShelfInsetContent(items: [item])
        case .sectioned:
            let item = TVTopShelfSectionedItem(identifier: plan.guid)
            item.title = plan.title
            switch plan.imageShape {
            case .poster: item.imageShape = .poster
            case .square, .hdtv: item.imageShape = .square
            }
            item.displayAction = TVTopShelfAction(url: plan.deepLink)
            applyImages(plan, to: item)
            let section = TVTopShelfItemCollection(items: [item])
            section.title = plan.sectionTitle
            return TVTopShelfSectionedContent(sections: [section])
        }
    }

    private static func applyImages(_ plan: TopShelfItemModel, to item: TVTopShelfItem) {
        if let url = plan.imageURL {
            item.setImageURL(url, forTraits: .screenScale1x)
        }
        if let url = plan.imageURL2x ?? plan.imageURL {
            item.setImageURL(url, forTraits: .screenScale2x)
        }
    }
}
