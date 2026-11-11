import AppIntents
import SwiftUI

enum CatalogEntityKind {
    case movie
    case episode
}

extension View {
    /// Marks the on-screen catalog item so "this movie" can fill Open Movie,
    /// the watchlist intents, Where to Watch, and Open on Provider.
    /// The identifier is the public catalog id. Ratings are not attached.
    func catalogEntity(_ kind: CatalogEntityKind, id: String, title: String) -> some View {
        modifier(CatalogEntityAnnotation(kind: kind, id: id, title: title))
    }
}

private struct CatalogEntityAnnotation: ViewModifier {
    var kind: CatalogEntityKind
    var id: String
    var title: String

    func body(content: Content) -> some View {
        #if os(iOS)
        annotated(content)
        #else
        content
        #endif
    }

    #if os(iOS)
    @ViewBuilder
    private func annotated(_ content: Content) -> some View {
        if #available(iOS 18.4, *) {
            let identifier = entityIdentifier
            content
                .appEntityIdentifier(identifier)
                .userActivity(activityType) { activity in
                    activity.title = title
                    // Spotlight for these items is the IndexedEntity donation.
                    // This activity only tells Siri what is on screen.
                    activity.isEligibleForSearch = false
                    activity.isEligibleForPrediction = false
                    activity.appEntityIdentifier = identifier
                }
        } else {
            content
        }
    }

    private var activityType: String {
        switch kind {
        case .movie: return "com.movieroulettetuesday.app.view-movie"
        case .episode: return "com.movieroulettetuesday.app.view-episode"
        }
    }

    @available(iOS 18.4, *)
    private var entityIdentifier: EntityIdentifier {
        switch kind {
        case .movie:
            return EntityIdentifier(for: MovieEntity.self, identifier: id)
        case .episode:
            return EntityIdentifier(for: EpisodeEntity.self, identifier: id)
        }
    }
    #endif
}
