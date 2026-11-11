import Foundation
#if os(iOS)
import AppIntents
import CoreSpotlight
#endif

/// Writes the public catalog and the public episode cache to Spotlight.
///
/// The arguments are the catalog and the RSS episodes only. Ratings and the
/// watchlist are not parameters, and the entities themselves don't carry them.
/// The app reindexes when those lists change. `IndexedEntityQuery` (iOS 27)
/// is not adopted here: that protocol is not in the iOS 18 SDK, and the launch
/// reindex covers the same public lists.
enum CatalogSpotlight {
    static let indexName = "MovieRouletteTuesdayCatalog"

    static func reindex(catalog: MovieCatalog?, episodes: [PodcastEpisode]) async {
        #if os(iOS)
        guard #available(iOS 18.0, *) else { return }
        await Indexer.write(catalog: catalog, episodes: episodes)
        #endif
    }
}

#if os(iOS)
@available(iOS 18.0, *)
private enum Indexer {
    static func write(catalog: MovieCatalog?, episodes: [PodcastEpisode]) async {
        let index = CSSearchableIndex(name: CatalogSpotlight.indexName)
        if let catalog {
            let movies = SpotlightDonation.movieEntities(catalog: catalog, episodes: episodes)
            await replace(movies, as: MovieEntity.self, in: index)
        }
        let episodeEntities = SpotlightDonation.episodeEntities(episodes)
        await replace(episodeEntities, as: EpisodeEntity.self, in: index)
    }

    /// Deletes the previous donation of this type, then writes the public list.
    /// An empty list clears the type so a movie that left the catalog drops out.
    private static func replace<Entity: IndexedEntity>(_ entities: [Entity], as type: Entity.Type, in index: CSSearchableIndex) async {
        try? await index.deleteAppEntities(ofType: type)
        guard !entities.isEmpty else { return }
        try? await index.indexAppEntities(entities)
    }
}
#endif
