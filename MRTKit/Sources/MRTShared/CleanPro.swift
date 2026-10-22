import SwiftUI
import MRTCore

/// "Clean Pro" design language: barely tinted gradient backgrounds, cards
/// with one layered soft shadow per container, large titles, and the wheel
/// hub as the spin button (teal->peach glow ring). Colors come from `CleanProColors` / `CategoryPalette`
/// (MRTCore) so the share card and widget match.
public enum CleanPro {
    public static let cardRadius: CGFloat = 18
    public static let spacing: CGFloat = 20

    public static func backgroundColors(_ scheme: ColorScheme) -> [Color] {
        (scheme == .dark ? CleanProColors.backgroundDark : CleanProColors.backgroundLight).map { Color(hex: $0) }
    }

    /// Card and list-row fill: the system grouped cell color, so cards and
    /// native list sections match exactly in light, dark and high contrast.
    /// tvOS has no grouped system colors: a fixed dark card (the TV app is dark only).
    #if os(tvOS)
    public static let cardFill = Color(hex: "#1C2427")
    #else
    public static let cardFill = Color(uiColor: .secondarySystemGroupedBackground)
    #endif

    public static func heading(_ scheme: ColorScheme) -> Color {
        Color(hex: scheme == .dark ? CleanProColors.headingDark : CleanProColors.headingLight)
    }

    public static func category(_ category: RouletteCategory?) -> Color {
        guard let category else { return Color(hex: "#8E8E93") }
        return Color(hex: category.displayHex)
    }
}

/// Full-screen tinted gradient (ignores safe areas).
public struct CleanProBackground: View {
    @Environment(\.colorScheme) private var scheme

    public init() {}

    public var body: some View {
        LinearGradient(colors: CleanPro.backgroundColors(scheme), startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

/// One container, one layered shadow (a tight contact shadow + a soft ambient one).
public struct CleanProCardBackground: View {
    public var cornerRadius: CGFloat = CleanPro.cardRadius
    @Environment(\.colorScheme) private var scheme

    public init(cornerRadius: CGFloat = CleanPro.cardRadius) {
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(CleanPro.cardFill)
            .shadow(color: .black.opacity(scheme == .dark ? 0.30 : 0.05), radius: 2, y: 1)
            .shadow(color: .black.opacity(scheme == .dark ? 0.25 : 0.07), radius: 14, y: 8)
    }
}

/// Titled card section used on scrolling (non-List) screens.
public struct CleanProSection<Content: View>: View {
    public let title: String?
    public var footer: String? = nil
    public let content: Content

    public init(_ title: String?, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 4)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .cleanProCard()
            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }
}

extension View {
    /// Pads the content and puts it on a Clean Pro card.
    public func cleanProCard(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { CleanProCardBackground() }
    }

    /// Lists and Forms: hide the default grouped background and show the
    /// Clean Pro gradient (rows keep the matching card fill).
    public func cleanProListScreen() -> some View {
        #if os(iOS)
        self.scrollContentBackground(.hidden)
            .background { CleanProBackground() }
        #else
        // tvOS has no scrollContentBackground; lists there draw no grouped background.
        self.background { CleanProBackground() }
        #endif
    }
}

/// Film-badge hub mark (teal reel disc with a peach frame), shared by the
/// wheel hub so it matches the approved mockup.
public struct FilmBadge: View {
    public let size: CGFloat
    @Environment(\.colorScheme) private var scheme

    public init(size: CGFloat) {
        self.size = size
    }

    public var body: some View {
        Image(systemName: "film.circle.fill")
            .symbolRenderingMode(.palette)
            .foregroundStyle(
                Color(hex: CleanProColors.peach),
                Color(hex: scheme == .dark ? CleanProColors.hubTealDark : CleanProColors.hubTealLight)
            )
            .font(.system(size: size, weight: .semibold))
            .accessibilityHidden(true)
    }
}
