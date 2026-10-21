import SwiftUI
import MRTCore

/// Anonymous listener poll for one episode (Episode detail). Results appear
/// after you vote, or right away if you can't vote (not signed into iCloud).
struct EpisodePollSection: View {
    let poll: PollDefinition
    @Environment(CommunityService.self) private var community

    private var myVote: String? { community.myVote(for: poll) }
    private var canVote: Bool { community.accountStatus.canWrite }
    private var isBusy: Bool { community.busy.contains(poll.id) }

    var body: some View {
        CleanProSection(
            "Listener Poll",
            footer: myVote != nil && canVote
                ? "Tap another answer to change your vote."
                : "One anonymous vote per iCloud account."
        ) {
            HStack {
                Text(poll.question)
                    .font(.headline)
                Spacer()
                if isBusy { ProgressView() }
            }
            // Attached to one row (not the Section) so it runs once.
            .task(id: poll.id) { await community.loadPoll(poll) }

            if community.canSeeResults(poll), let results = community.pollResults[poll.id] {
                ForEach(results.rows, id: \.option.id) { row in
                    resultRow(row)
                }
                Text(results.total == 1 ? "1 vote" : "\(results.total) votes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(poll.options) { option in
                    Button {
                        Task { await community.vote(poll, option: option) }
                    } label: {
                        Text(option.label)
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(Brand.accentTeal)
                    .disabled(!canVote || isBusy)
                }
                if canVote {
                    Label("Vote to see results", systemImage: "eye.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let message = community.accountMessage {
                Label(message, systemImage: "icloud.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let error = community.errors[poll.id] {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func resultRow(_ row: PollResults.Row) -> some View {
        let isMine = row.option.id == myVote
        return Button {
            guard !isMine else { return }
            Task { await community.vote(poll, option: row.option) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(row.option.label)
                        .font(.body.weight(isMine ? .bold : .regular))
                    if isMine {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Brand.accentTeal)
                            .accessibilityLabel("Your vote")
                    }
                    Spacer()
                    Text(row.fraction, format: .percent.precision(.fractionLength(0)))
                        .font(.body.monospacedDigit().weight(.semibold))
                    Text(verbatim: "(\(row.count))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: row.fraction)
                    .tint(isMine ? Brand.accentTeal : Brand.accentPeach)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canVote || isBusy)
    }
}

#Preview {
    ScrollView {
        EpisodePollSection(poll: PollFactory.defaultPoll(forEpisode: "Buzzsprout-1", hosts: ShowInfo.mrt.hosts))
            .padding()
    }
    .environment(CommunityService.preview())
}
