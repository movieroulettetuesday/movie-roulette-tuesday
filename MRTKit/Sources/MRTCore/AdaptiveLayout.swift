import Foundation

/// Pure layout decisions for iPhone + iPad. Views pass in their horizontal
/// size class (as `isRegularWidth`) and available size, never the device
/// type, so iPad Split View / Slide Over at narrow widths gets the iPhone layout.
///
/// The wheel is sized from the slot it actually gets (after the header has
/// taken its space and the "Tap to spin" hint under the wheel is reserved), so it
/// fills the screen on large phones and
/// shrinks on small phones, short windows and at large Dynamic Type sizes
/// instead of crowding the text. The diameter depends only on the slot size, so
/// labels never resize mid-spin.
public struct RouletteLayout: Equatable, Sendable {
    public enum Arrangement: Equatable, Sendable {
        /// Header, then wheel + hint in one column (iPhone, iPad portrait, narrow iPad windows).
        case stacked
        /// Wheel + hint on the left; header on the right (wide regular-width windows).
        case sideBySide
    }

    public let arrangement: Arrangement

    /// Side margin around the wheel in compact width. The hub is the spin
    /// button (no SPIN pill), so the wheel takes the freed space (approved B2).
    public static let compactSideMargin = 10.0
    /// Gap between the wheel and the "Tap to spin" hint under it.
    public static let hintSpacing = 14.0
    /// Upper bounds, so huge windows get a big but not absurd wheel.
    public static let compactCap = 560.0
    public static let regularStackedCap = 820.0
    public static let sideBySideCap = 860.0
    /// Below this the slot is degenerate (mid-rotation, zero-size first pass).
    public static let minimumDiameter = 120.0
    /// Room kept under the wheel for its drop shadow (radius 18, y 10).
    public static let shadowAllowance = 24.0
    /// Breathing room above the pointer (keeps it clear of the subtitle).
    public static let topGap = 14.0

    public init(arrangement: Arrangement) {
        self.arrangement = arrangement
    }

    public static func make(width: Double, height: Double, isRegularWidth: Bool) -> RouletteLayout {
        let w = sane(width), h = sane(height)
        let landscapeEnough = w >= 700 && w > h * 1.15
        return RouletteLayout(arrangement: isRegularWidth && landscapeEnough ? .sideBySide : .stacked)
    }

    /// Width of the controls column in the side-by-side layout.
    public static func sideBySideControlsWidth(forWidth width: Double) -> Double {
        min(360, max(240, sane(width) * 0.3))
    }

    /// Pointer (arrow) size for a wheel, scaled with it (28x34 pt at the old ~290 pt iPhone wheel).
    public static func pointerSize(forDiameter diameter: Double) -> (width: Double, height: Double) {
        let w = min(max(sane(diameter) * 0.085, 28), 56)
        return (w, w * 34 / 28)
    }

    /// Height the wheel view occupies: the pointer overhangs the top by half its height.
    public static func wheelFrameHeight(forDiameter diameter: Double) -> Double {
        diameter + pointerSize(forDiameter: diameter).height / 2
    }

    /// Wheel diameter for the slot it is centered in.
    /// - stacked, compact: full width minus 10 pt margins (about 95% of an iPhone).
    /// - stacked, regular (iPad portrait, 2/3 Split View): 84% of the width.
    /// - side by side: the whole wheel pane.
    /// Always capped by height so the pointer, wheel, shadow and the hint below
    /// (`hintHeight` + `hintSpacing`; 0 = no hint) fit the slot.
    public static func wheelDiameter(slotWidth: Double, slotHeight: Double,
                                     arrangement: Arrangement, isRegularWidth: Bool,
                                     hintHeight: Double = 0) -> Double {
        let hint = sane(hintHeight)
        let w = sane(slotWidth), h = sane(slotHeight) - (hint > 0 ? hint + hintSpacing : 0)
        var d: Double
        switch arrangement {
        case .sideBySide:
            d = min(w, sideBySideCap)
        case .stacked where isRegularWidth:
            d = min(w * 0.84, regularStackedCap)
        case .stacked:
            d = min(w - 2 * compactSideMargin, compactCap)
        }
        // The pointer grows with the wheel; three passes settle the fixed point.
        for _ in 0..<3 {
            d = min(d, h - pointerSize(forDiameter: d).height / 2 - shadowAllowance - topGap)
        }
        guard d.isFinite else { return minimumDiameter }
        return max(minimumDiameter, d)
    }

    private static func sane(_ v: Double) -> Double { v.isFinite ? max(0, v) : 0 }
}

/// Columns for the Stats tab card grid (regular width only; compact uses a List).
public enum StatsGridLayout {
    public static func columnCount(forWidth width: Double, isRegularWidth: Bool) -> Int {
        guard isRegularWidth, width.isFinite else { return 1 }
        if width >= 1_100 { return 3 }
        if width >= 640 { return 2 }
        return 1
    }
}

/// Confetti density / piece size scaled to the presenting width, so a big
/// iPad sheet isn't sparse and an iPhone stays light.
public enum ConfettiScale {
    public static let baseWidth = 430.0

    public static func particleCount(forWidth width: Double, base: Int = 60) -> Int {
        guard width.isFinite, width > 0 else { return base }
        let scaled = Double(base) * width / baseWidth
        return Int(min(max(scaled, Double(base)), Double(base) * 2.5).rounded())
    }

    public static func pieceScale(forWidth width: Double) -> Double {
        guard width.isFinite, width > 0 else { return 1 }
        return min(max(width / baseWidth, 1), 1.6)
    }
}

/// `mrt://movie/<id>`: opens a movie page (from the widget or elsewhere).
/// `mrt://episode/<guid>`: opens an episode page (new-episode notification).
public enum DeepLink: Equatable, Sendable {
    case movie(id: String)
    case episode(guid: String)

    public static let scheme = "mrt"

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let host = (components.host ?? "").lowercased()
        // Split the still-encoded path so an escaped "/" inside an id survives.
        let parts = components.percentEncodedPath.split(separator: "/").map(String.init)
        // mrt://movie/<id>  (also tolerate mrt:///movie/<id>)
        let segments = host.isEmpty ? parts : [host] + parts
        guard segments.count == 2 else { return nil }
        let id = segments[1].removingPercentEncoding ?? segments[1]
        guard !id.isEmpty, id.count <= 200 else { return nil }
        switch segments[0].lowercased() {
        case "movie": self = .movie(id: id)
        case "episode": self = .episode(guid: id)
        default: return nil
        }
    }

    public var url: URL {
        let (host, id): (String, String)
        switch self {
        case .movie(let movieID): (host, id) = ("movie", movieID)
        case .episode(let guid): (host, id) = ("episode", guid)
        }
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = host
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        components.percentEncodedPath = "/" + (id.addingPercentEncoding(withAllowedCharacters: allowed) ?? id)
        return components.url ?? URL(string: "mrt://\(host)")!
    }
}
