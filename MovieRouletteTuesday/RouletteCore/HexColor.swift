import Foundation

/// Parsed "#RRGGBB" / "#RRGGBBAA" color (components 0...1), UI-framework free.
public struct HexColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init?(_ hex: String) {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasPrefix("#") { string.removeFirst() }
        guard string.count == 6 || string.count == 8,
              string.allSatisfy(\.isHexDigit),
              let value = UInt64(string, radix: 16) else { return nil }
        if string.count == 6 {
            red = Double((value >> 16) & 0xFF) / 255
            green = Double((value >> 8) & 0xFF) / 255
            blue = Double(value & 0xFF) / 255
            alpha = 1
        } else {
            red = Double((value >> 24) & 0xFF) / 255
            green = Double((value >> 16) & 0xFF) / 255
            blue = Double((value >> 8) & 0xFF) / 255
            alpha = Double(value & 0xFF) / 255
        }
    }

    /// WCAG relative luminance (0 = black, 1 = white).
    public var relativeLuminance: Double {
        func linear(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// True when black text has better WCAG contrast on this color than white.
    public var prefersDarkText: Bool {
        let contrastWithBlack = (relativeLuminance + 0.05) / 0.05
        let contrastWithWhite = 1.05 / (relativeLuminance + 0.05)
        return contrastWithBlack > contrastWithWhite
    }

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        func clamp(_ v: Double) -> Double { v.isFinite ? min(max(v, 0), 1) : 0 }
        self.red = clamp(red)
        self.green = clamp(green)
        self.blue = clamp(blue)
        self.alpha = clamp(alpha)
    }

    /// From hue/saturation/brightness (all 0...1).
    public init(hue: Double, saturation: Double, brightness: Double, alpha: Double = 1) {
        let h = (hue.isFinite ? hue - floor(hue) : 0) * 6
        let s = min(max(saturation.isFinite ? saturation : 0, 0), 1)
        let v = min(max(brightness.isFinite ? brightness : 0, 0), 1)
        let i = Int(h) % 6
        let f = h - floor(h)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        let (r, g, b): (Double, Double, Double)
        switch i {
        case 0: (r, g, b) = (v, t, p)
        case 1: (r, g, b) = (q, v, p)
        case 2: (r, g, b) = (p, v, t)
        case 3: (r, g, b) = (p, q, v)
        case 4: (r, g, b) = (t, p, v)
        default: (r, g, b) = (v, p, q)
        }
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }

    public var hsb: (hue: Double, saturation: Double, brightness: Double) {
        let maxC = max(red, green, blue), minC = min(red, green, blue)
        let delta = maxC - minC
        var hue = 0.0
        if delta > 0 {
            if maxC == red { hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6) }
            else if maxC == green { hue = (blue - red) / delta + 2 }
            else { hue = (red - green) / delta + 4 }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        return (hue, maxC == 0 ? 0 : delta / maxC, maxC)
    }

    /// "#RRGGBB" (alpha dropped).
    public var hexString: String {
        func byte(_ c: Double) -> Int { Int((c * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }
}
