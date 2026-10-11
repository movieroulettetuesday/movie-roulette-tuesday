import Foundation

/// The single source of category colors for every surface (wheel, dots,
/// Stats, history, reveal, share card, widget).
///
/// Known show categories use the muted "Clean Pro" palette, keyed by category
/// id. A category the app doesn't know yet (e.g. from a newer remote catalog)
/// gets a muted version of its catalog `colorHex`; with no usable hex, a
/// stable pick from the palette based on its id. `movies.json` colors are
/// only that fallback input.
public enum CategoryPalette {
    public static let known: [String: String] = [
        "cat-horror": "#C25B5E",
        "cat-cult": "#8670AE",
        "cat-criterion": "#CFAE63",
        "cat-love": "#C66E8E",
        "cat-scifi": "#4D97C2",
        "cat-action": "#D4884F",
        "cat-dark-comedy": "#4A988B",
        "cat-listener": "#5E7DC0",
        "cat-prestige": "#9086A1",
        "cat-escape": "#977758",
    ]

    /// Ordered fallback picks (same muted family).
    public static let fallback: [String] = [
        "#C25B5E", "#8670AE", "#CFAE63", "#C66E8E", "#4D97C2",
        "#D4884F", "#4A988B", "#5E7DC0", "#9086A1", "#977758",
    ]

    public static func hex(forCategoryId id: String, catalogHex: String? = nil) -> String {
        if let mapped = known[id] { return mapped }
        if let catalogHex, let parsed = HexColor(catalogHex) {
            return muted(parsed).hexString
        }
        return fallback[stableIndex(id, count: fallback.count)]
    }

    /// Pulls a saturated catalog color into the muted family: lower
    /// saturation, brightness kept in a band that works with white or ink labels.
    public static func muted(_ color: HexColor) -> HexColor {
        let hsb = color.hsb
        return HexColor(hue: hsb.hue,
                        saturation: min(hsb.saturation * 0.7, 0.5),
                        brightness: min(max(hsb.brightness, 0.58), 0.8))
    }

    /// Gentle radial gradient for a wheel segment: lighter, softer center ->
    /// base color -> slightly deeper edge.
    public static func radialStops(_ hex: String) -> [String] {
        guard let base = HexColor(hex) else { return [hex, hex, hex] }
        let hsb = base.hsb
        let center = HexColor(hue: hsb.hue, saturation: hsb.saturation * 0.55, brightness: min(1, hsb.brightness * 1.2))
        let edge = HexColor(hue: hsb.hue, saturation: hsb.saturation, brightness: hsb.brightness * 0.9)
        return [center.hexString, base.hexString, edge.hexString]
    }

    /// FNV-1a: stable across launches and devices (unlike `hashValue`).
    static func stableIndex(_ id: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return Int(hash % UInt64(count))
    }
}

extension RouletteCategory {
    /// The color to draw this category with everywhere in the UI.
    public var displayHex: String {
        CategoryPalette.hex(forCategoryId: id, catalogHex: colorHex)
    }
}

/// Fixed Clean Pro theme colors shared by the app, share card and widget.
public enum CleanProColors {
    public static let backgroundLight = ["#F8F8F8", "#EAF3F4"]
    public static let backgroundDark = ["#0E1214", "#101A1C"]
    /// Brand teal -> deeper teal -> peach ramp (formerly the SPIN pill; white text sits on the middle stop).
    public static let spinGradient = ["#3A9CA6", "#2E8691", "#E39B5E"]
    public static let spinLabelStop = "#2E8691"
    public static let rimLight = ["#FFFFFF", "#F1F3F4", "#FFFFFF"]
    public static let rimDark = ["#2A3236", "#3A4448", "#2A3236"]
    public static let hubDiscLight = "#FFFFFF"
    public static let hubDiscDark = "#1C2427"
    public static let hubTealLight = "#3A9CA6"
    public static let hubTealDark = "#3FA9B3"
    public static let peach = "#F7C08A"
    public static let pointerLight = "#2E8691"
    public static let pointerDark = "#5BB8C2"
    /// Small heading text on the light/dark backgrounds (contrast >= 4.5).
    public static let headingLight = "#24646B"
    public static let headingDark = "#F7C08A"
}

/// WCAG contrast ratio between two colors (1...21).
public func contrastRatio(_ a: HexColor, _ b: HexColor) -> Double {
    let la = a.relativeLuminance, lb = b.relativeLuminance
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
}
