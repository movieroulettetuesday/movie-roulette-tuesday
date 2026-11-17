import SwiftUI

/// Removable chips for a parsed NL search question. Same capsule style as the
/// Movies "On my services" chips; stacked at accessibility text sizes.
struct NLSearchChipsSection: View {
    let chips: [NLSearch.Chip]
    let remove: (NLSearch.ChipField) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if !chips.isEmpty {
            Section {
                let row = ForEach(chips) { chip in
                    Button {
                        remove(chip.field)
                    } label: {
                        HStack(spacing: 6) {
                            Text(chip.label)
                            Image(systemName: "xmark.circle.fill")
                                .imageScale(.small)
                                .accessibilityHidden(true)
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Brand.tealDark, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(chip.label)
                    .accessibilityHint("Removes this filter")
                    .accessibilityIdentifier("nl-chip-\(chip.id)")
                }
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 8) { row }
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) { row }
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
        }
    }
}
