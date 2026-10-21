import SwiftUI
import MRTCore

public enum Brand {
    // Fixed brand values sampled from the show logo. Identical in light and
    // dark mode: used by the share card and on fixed-color fills (banners).
    public static let teal = Color(hex: "#3A9CA6")
    public static let tealDark = Color(hex: "#24646B")
    public static let peach = Color(hex: "#F7C08A")
    public static let ink = Color(hex: "#1D2B2E")
    public static let jackpotGold = Color(hex: "#F2C14E")

    // Adaptive UI colors (asset catalog, light + dark variants tuned for
    // contrast against systemBackground). Use these for foreground icons,
    // tints, and progress bars in normal UI.
    public static let accentTeal = Color("BrandTeal")
    public static let accentPeach = Color("BrandPeach")
    public static let wheelRim = Color("WheelRim")
}
