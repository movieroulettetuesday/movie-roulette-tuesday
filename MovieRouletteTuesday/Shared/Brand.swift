import SwiftUI
import MRTCore

enum Brand {
    // Fixed brand values sampled from the show logo. Identical in light and
    // dark mode: used by the share card and on fixed-color fills (banners).
    static let teal = Color(hex: "#3A9CA6")
    static let tealDark = Color(hex: "#24646B")
    static let peach = Color(hex: "#F7C08A")
    static let ink = Color(hex: "#1D2B2E")
    static let jackpotGold = Color(hex: "#F2C14E")

    // Adaptive UI colors (asset catalog, light + dark variants tuned for
    // contrast against systemBackground). Use these for foreground icons,
    // tints, and progress bars in normal UI.
    static let accentTeal = Color("BrandTeal")
    static let accentPeach = Color("BrandPeach")
    static let wheelRim = Color("WheelRim")
}
