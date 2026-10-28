import SwiftUI
import MRTCore
import MRTShared

/// Mockup colors, switching with the system appearance. Dark values match gen.py
/// (TEAL, WHITE, GREY). Light uses the Clean Pro ink on a light field.
struct TVTheme {
    var scheme: ColorScheme

    var text: Color { scheme == .dark ? Color(hex: "#F5F7F7") : Color(hex: "#1D2B2E") }
    var secondary: Color { scheme == .dark ? Color(hex: "#96A2A5") : Color(hex: "#5E6C70") }
    var card: Color { scheme == .dark ? Color(hex: "#1B2427") : Color(hex: "#FFFFFF") }
    var cardAlt: Color { scheme == .dark ? Color(hex: "#243033") : Color(hex: "#E7EEEF") }
    var pill: Color { scheme == .dark ? Color(hex: "#2E393C") : Color(hex: "#D5DEE0") }
    var field: Color { scheme == .dark ? Color(hex: "#121A1C") : Color(hex: "#FFFFFF") }
    var ink: Color { Color(hex: "#0A0A0A") }
    var teal: Color { Brand.teal }
    var isDark: Bool { scheme == .dark }

    /// Hairline so a white card still reads on a light background.
    var cardStroke: Color { scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.08) }
}

/// Fixed brand samples kept for call sites that don't have a theme yet.
enum TVPalette {
    static let teal = Brand.teal
    static let white = Color(hex: "#F5F7F7")
    static let grey = Color(hex: "#96A2A5")
    static let ink = Color(hex: "#0A0A0A")
    static let pill = Color(hex: "#2E393C")
}

/// The mockups' pill button: focused = white fill, teal glow, ~8% larger.
struct TVPillButtonStyle: ButtonStyle {
    var primary = true
    var width: CGFloat = 520
    var height: CGFloat = 132
    var fontSize: CGFloat = 40

    func makeBody(configuration: Configuration) -> some View {
        TVPill(configuration: configuration, primary: primary, width: width, height: height, fontSize: fontSize)
    }

    private struct TVPill: View {
        let configuration: ButtonStyleConfiguration
        let primary: Bool
        let width: CGFloat
        let height: CGFloat
        let fontSize: CGFloat
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            let fill: Color = isFocused ? TVPalette.white : (primary ? TVPalette.white.opacity(0.85) : TVPalette.pill)
            let text: Color = (isFocused || primary) ? TVPalette.ink : TVPalette.white
            configuration.label
                .font(.system(size: fontSize, weight: .bold))
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

/// Full-width row that turns white under focus (episode rows, settings, recent spins).
struct TVRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TVRow(configuration: configuration)
    }

    private struct TVRow: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var isFocused
        @Environment(\.colorScheme) private var scheme

        var body: some View {
            let theme = TVTheme(scheme: scheme)
            configuration.label
                .foregroundStyle(isFocused ? theme.ink : theme.text)
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(isFocused ? Color.white : theme.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(isFocused ? Color.clear : theme.cardStroke, lineWidth: 2)
                )
                .shadow(color: theme.teal.opacity(isFocused ? 0.65 : 0), radius: isFocused ? 22 : 0)
                .scaleEffect(isFocused ? (configuration.isPressed ? 1.02 : 1.04) : 1)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}

/// Plain button whose label draws its own focus chrome (movie cards, provider tiles).
struct TVPlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

/// Category chip: colored capsule with a white dot and contrasting label.
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

/// Hides a tab badge when the count is zero (`.badge(0)` can still draw a dot).
struct TVBadge: ViewModifier {
    let count: Int
    func body(content: Content) -> some View {
        if count > 0 { content.badge(count) } else { content }
    }
}
