import SwiftUI

struct RulesSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// iPad (regular-width presenter): full form sheet, no partial detent.
    var presenterIsRegularWidth = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Tap the glowing hub in the middle of the wheel, or anywhere on the wheel, to spin.", image: "roulette.wheel")
                    Label("The arrow at the top picks a theme category — grounded in the show’s rotating rounds (Horror, Criterion, Love Hurts, Listener Picks, and more).", systemImage: "arrowtriangle.down.fill")
                    Label("Then a film from that category is drawn. Recent spins are less likely to repeat; every title was actually discussed on Movie Roulette Tuesday.", systemImage: "film.stack")
                    Label("Open Episodes for the full Buzzsprout feed, Movies to browse the catalog, and Stats for your local spin history.", systemImage: "menubar.dock.rectangle")
                    Label("Spins and the episode cache stay on this device.", systemImage: "iphone")
                } footer: {
                    Text("Dinner, discussion, and dice. Spin responsibly.")
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
