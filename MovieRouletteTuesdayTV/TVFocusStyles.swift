import SwiftUI
import MRTCore
import MRTShared

/// Mockup colors (gen.py: TEAL, WHITE, GREY) at 10-foot scale.
enum TVPalette {
    static let teal = Brand.teal
    static let white = Color(hex: "#F5F7F7")
    static let grey = Color(hex: "#96A2A5")
    static let ink = Color(hex: "#0A0A0A")
    /// Unfocused secondary pill (mockup "Movie Page").
    static let pill = Color(hex: "#2E393C")
}

/// The mockups' pill button: focused = white fill, teal glow, ~8% larger;
/// unfocused primary = white at lower contrast, secondary = dark grey.
/// Replaces the default tvOS lift effect so the look matches the mockups.
struct TVPillButtonStyle: ButtonStyle {
    var primary = true
    var width: CGFloat = 520
    var height: CGFloat = 132

    func makeBody(configuration: Configuration) -> some View {
        TVPill(configuration: configuration, primary: primary, width: width, height: height)
    }

    private struct TVPill: View {
        let configuration: ButtonStyleConfiguration
        let primary: Bool
        let width: CGFloat
        let height: CGFloat
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            let fill: Color = isFocused ? TVPalette.white : (primary ? TVPalette.white.opacity(0.85) : TVPalette.pill)
            let text: Color = (isFocused || primary) ? TVPalette.ink : TVPalette.white
            configuration.label
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(text)
                .frame(width: width, height: height)
                .background(Capsule().fill(fill))
                .overlay(Capsule().strokeBorder(TVPalette.teal.opacity(isFocused ? 0.9 : 0), lineWidth: 4))
                .shadow(color: TVPalette.teal.opacity(isFocused ? 0.7 : 0), radius: isFocused ? 24 : 0)
                .scaleEffect(isFocused ? (configuration.isPressed ? 1.04 : 1.08) : 1)
                .animation(.easeOut(duration: 0.15), value: isFocused)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}

/// Category chip: colored capsule with a white dot and dark label (mockups 01/02).
struct TVCategoryChip: View {
    let category: RouletteCategory
    var text: String? = nil
    var size: CGFloat = 32

    var body: some View {
        HStack(spacing: size * 0.4) {
            Circle().fill(Color.white).frame(width: size * 0.5, height: size * 0.5)
            Text(text ?? category.name)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Color.labelColor(onHex: category.displayHex))
                .lineLimit(1)
        }
        .padding(.horizontal, size * 0.75)
        .padding(.vertical, size * 0.3)
        .background(Capsule().fill(Color(hex: category.displayHex)))
    }
}
