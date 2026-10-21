import SwiftUI
import MRTCore

extension Color {
    /// "#RRGGBB" / "#RRGGBBAA" -> Color (sRGB). Invalid strings use `fallback`.
    init(hex: String, fallback: Color = .gray) {
        guard let parsed = HexColor(hex) else {
            self = fallback
            return
        }
        self = Color(.sRGB, red: parsed.red, green: parsed.green, blue: parsed.blue, opacity: parsed.alpha)
    }

    /// Black or white, whichever reads better on the given background hex.
    static func labelColor(onHex hex: String) -> Color {
        HexColor(hex)?.prefersDarkText == true ? Color.black.opacity(0.85) : Color.white
    }
}
