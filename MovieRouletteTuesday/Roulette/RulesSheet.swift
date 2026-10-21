import SwiftUI
import MRTCore
import MRTShared

struct RulesSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// iPad (regular-width presenter): full form sheet, no partial detent.
    var presenterIsRegularWidth = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Tap the glowing hub, or anywhere on the wheel, to spin. While it spins, tap the ■ in the center to stop early.", image: "roulette.wheel")
                    Label("The arrow at the top picks a theme category, like Horror, Criterion, Love Hurts or Listener Picks.", systemImage: "arrowtriangle.down.fill")
                    Label("Then a movie from that category is drawn. Recent spins are less likely to repeat, and every title was discussed on the show.", systemImage: "film.stack")
                } footer: {
                    Text("Dinner, discussion, and the wheel. Spin responsibly.")
                }
                .labelStyle(RuleLabelStyle())
            }
            .cleanProListScreen()
            .navigationTitle("House Rules")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents(presenterIsRegularWidth ? [.large] : [.medium, .large])
    }
}

/// Teal icon column + generous row padding (Clean Pro list rows).
private struct RuleLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            configuration.icon
                .foregroundStyle(Brand.accentTeal)
                .frame(minWidth: 24)
            configuration.title
        }
        .padding(.vertical, 6)
    }
}
