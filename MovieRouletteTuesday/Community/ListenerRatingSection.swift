import SwiftUI

/// Community (anonymous) average for a movie plus this user's listener vote.
/// Separate from "My rating", which stays on the device unless shared.
struct ListenerRatingSection: View {
    let movieId: String
    /// The local "My rating" in half-stars (Part of Your Take), offered for sharing.
    let myRating: Int?
    @Environment(CommunityService.self) private var community

    private var aggregate: RatingAggregate? { community.ratingAggregates[movieId] }
    private var shared: Int? { community.myListenerRating(movieId: movieId) }
    private var canWrite: Bool { community.accountStatus.canWrite }
    private var isBusy: Bool { community.busy.contains(movieId) }

    var body: some View {
        CleanProSection(
            "Listener Rating",
            footer: "Shared anonymously through iCloud; only the movie and star count are stored."
        ) {
            HStack(spacing: 10) {
                if let aggregate, let average = aggregate.average {
                    Text(HalfStars.label(stars: average))
                        .font(.title2.bold().monospacedDigit())
                    StarRatingView(halfStars: aggregate.averageHalfStars, font: .subheadline, tint: Brand.accentPeach)
                    Spacer()
                    Text(aggregate.count == 1 ? "1 rating" : "\(aggregate.count) ratings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if aggregate == nil, community.errors[movieId] == nil {
                    Text("Loading listener ratings…").foregroundStyle(.secondary)
                    Spacer()
                    ProgressView()
                } else {
                    Text("No listener ratings yet").foregroundStyle(.secondary)
                }
            }
            .task(id: movieId) { await community.loadRating(movieId: movieId) }

            if let shared {
                LabeledContent("Your listener rating") {
                    StarRatingView(halfStars: shared, font: .caption, tint: Brand.accentPeach)
                }
            }

            if canWrite {
                if let myRating, myRating != shared {
                    Button {
                        Task { await community.submitListenerRating(movieId: movieId, halfStars: myRating) }
                    } label: {
                        Label(shared == nil ? "Add my \(HalfStars.label(myRating)) ★ rating to the listener average"
                                            : "Update my listener rating to \(HalfStars.label(myRating)) ★",
                              systemImage: "person.3.fill")
                    }
                    .disabled(isBusy)
                } else if myRating == nil, shared == nil {
                    Text("Rate it under Your Rating to add your stars.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if let message = community.accountMessage {
                Label(message, systemImage: "icloud.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let error = community.errors[movieId] {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }
}

#Preview {
    ScrollView {
        ListenerRatingSection(movieId: "the-room-2003", myRating: 7)
            .padding()
    }
    .environment(CommunityService.preview())
}
