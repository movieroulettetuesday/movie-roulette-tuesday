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

    /// Hub disc as a fraction of the wheel diameter. Shared with the drawn hub
    /// and the spin button so hinge clearance matches the control.
    public static let hubDiameterFraction = 0.23
    /// Glow ring drawn `hubSize + 10` around the spin button (`HubSpinButton`).
    public static let hubRingOutset = 10.0
    /// Minimum hit area for the hub Spin / Stop control (HIG). The drawn disc
    /// stays `hubVisualDiameter`; only the tappable frame is expanded when the
    /// wheel is small enough that `diameter × hubDiameterFraction` would drop
    /// below 44 pt (below about 191 pt, including `minimumDiameter` 120).
    public static let minimumHubHitSize = 44.0

    /// Drawn hub disc diameter (visuals only).
    public static func hubVisualDiameter(forWheelDiameter diameter: Double) -> Double {
        sane(diameter) * hubDiameterFraction
    }

    /// Tappable width and height of the hub Spin / Stop control, at least
    /// `minimumHubHitSize`. At `minimumDiameter` this is 44, not 27.6.
    public static func hubHitSize(forWheelDiameter diameter: Double) -> Double {
        max(minimumHubHitSize, hubVisualDiameter(forWheelDiameter: diameter))
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

    /// Square that must stay off an active hinge: the hub disc plus its glow ring,
    /// in the wheel slot's coordinates (origin at the slot's top-left).
    public static func hubFrame(slotWidth: Double, slotHeight: Double,
                                diameter: Double, hintHeight: Double) -> LayoutRect {
        let placed = placedWheel(slotWidth: slotWidth, slotHeight: slotHeight,
                                 diameter: diameter, hintHeight: hintHeight)
        let side = placed.diameter * hubDiameterFraction + hubRingOutset
        let centerY = placed.stackTop + placed.pointerHeight / 2 + placed.diameter / 2
        return LayoutRect(x: placed.centerX - side / 2, y: centerY - side / 2, width: side, height: side)
    }

    /// The wheel view (face, rim, pointer), not the hint under it.
    public static func wheelFrame(slotWidth: Double, slotHeight: Double,
                                  diameter: Double, hintHeight: Double) -> LayoutRect {
        let placed = placedWheel(slotWidth: slotWidth, slotHeight: slotHeight,
                                 diameter: diameter, hintHeight: hintHeight)
        return LayoutRect(x: placed.centerX - placed.diameter / 2, y: placed.stackTop,
                          width: placed.diameter, height: placed.wheelHeight)
    }

    /// Moves the centered wheel so its hub misses every active division rectangle.
    ///
    /// `divisions` are in the same top-left coordinates as `hub` and `wheel`
    /// (the wheel slot). An empty list — no hinge, or the hinge is inactive —
    /// returns `.zero`, which is the iPhone, iPad, and fully-open layout.
    /// The result is a pure function of the current slot, so a fold during a
    /// spin is just the next layout pass. A second call on the shifted hub
    /// returns `.zero`: the wheel does not walk across repeated passes.
    public static func hingeClearanceOffset(hub: LayoutRect, wheel: LayoutRect,
                                             slot: LayoutRect, divisions: [LayoutRect]) -> LayoutOffset {
        guard slot.width > 0, slot.height > 0, hub.isUsable, wheel.isUsable else { return .zero }
        let bands = divisions.filter(\.isUsable).sorted {
            if $0.y != $1.y { return $0.y < $1.y }
            return $0.x < $1.x
        }
        guard !bands.isEmpty else { return .zero }
        var dx = 0.0
        var dy = 0.0
        for _ in 0..<bands.count {
            var moved = false
            for band in bands {
                let placedHub = hub.offsetBy(dx: dx, dy: dy)
                let before = bands.reduce(0) { $0 + (placedHub.intersects($1) ? 1 : 0) }
                let step = separation(
                    hub: placedHub,
                    wheel: wheel.offsetBy(dx: dx, dy: dy),
                    slot: slot,
                    band: band
                )
                guard step != .zero else { continue }
                let afterHub = hub.offsetBy(dx: dx + step.x, dy: dy + step.y)
                let after = bands.reduce(0) { $0 + (afterHub.intersects($1) ? 1 : 0) }
                // Reject a step that would slide the hub back onto another band.
                guard after < before else { continue }
                dx += step.x
                dy += step.y
                moved = true
            }
            if !moved { break }
        }
        guard dx.isFinite, dy.isFinite else { return .zero }
        return LayoutOffset(x: dx, y: dy)
    }

    private struct PlacedWheel {
        var centerX: Double
        var stackTop: Double
        var diameter: Double
        var pointerHeight: Double
        var wheelHeight: Double
    }

    /// Same centering as `RouletteView`'s wheel slot: the wheel and the hint
    /// under it are centered in the slot, and the hub sits in the middle of the face.
    private static func placedWheel(slotWidth: Double, slotHeight: Double,
                                    diameter: Double, hintHeight: Double) -> PlacedWheel {
        let slotW = sane(slotWidth), slotH = sane(slotHeight)
        let d = sane(diameter)
        let hint = sane(hintHeight)
        let pointer = pointerSize(forDiameter: d)
        let wheelHeight = wheelFrameHeight(forDiameter: d)
        let stackHeight = wheelHeight + (hint > 0 ? hint + hintSpacing : 0)
        return PlacedWheel(
            centerX: slotW / 2,
            stackTop: (slotH - stackHeight) / 2,
            diameter: d,
            pointerHeight: pointer.height,
            wheelHeight: wheelHeight
        )
    }

    /// One band. A band that is at least as tall as it is wide is a vertical
    /// hinge (book fold); otherwise it runs horizontally (tabletop fold).
    private static func separation(hub: LayoutRect, wheel: LayoutRect,
                                   slot: LayoutRect, band: LayoutRect) -> LayoutOffset {
        guard hub.intersects(band) else { return .zero }
        if band.width <= band.height {
            return LayoutOffset(x: axisShift(hub: hub, wheel: wheel, slot: slot, band: band, horizontal: true), y: 0)
        }
        return LayoutOffset(x: 0, y: axisShift(hub: hub, wheel: wheel, slot: slot, band: band, horizontal: false))
    }

    private static func axisShift(hub: LayoutRect, wheel: LayoutRect, slot: LayoutRect,
                                  band: LayoutRect, horizontal: Bool) -> Double {
        let hubMin = horizontal ? hub.minX : hub.minY
        let hubMax = horizontal ? hub.maxX : hub.maxY
        let bandMin = horizontal ? band.minX : band.minY
        let bandMax = horizontal ? band.maxX : band.maxY
        let slotMin = horizontal ? slot.minX : slot.minY
        let slotMax = horizontal ? slot.maxX : slot.maxY
        let towardNegative = bandMin - hubMax
        let towardPositive = bandMax - hubMin
        let negativePane = bandMin - slotMin
        let positivePane = slotMax - bandMax
        let preferNegative = negativePane > positivePane
        let ordered = preferNegative ? [towardNegative, towardPositive] : [towardPositive, towardNegative]

        func fits(_ delta: Double, keeping container: LayoutRect) -> Bool {
            let moved = horizontal ? container.offsetBy(dx: delta, dy: 0) : container.offsetBy(dx: 0, dy: delta)
            let movedHub = horizontal ? hub.offsetBy(dx: delta, dy: 0) : hub.offsetBy(dx: 0, dy: delta)
            return !movedHub.intersects(band) && contains(slot, moved) && contains(slot, movedHub)
        }
        for delta in ordered where fits(delta, keeping: wheel) {
            return delta
        }
        func hubClears(_ delta: Double) -> Bool {
            let movedHub = horizontal ? hub.offsetBy(dx: delta, dy: 0) : hub.offsetBy(dx: 0, dy: delta)
            return !movedHub.intersects(band) && contains(slot, movedHub)
        }
        for delta in ordered where hubClears(delta) {
            return delta
        }
        let roomNegative = slotMin - hubMin
        let roomPositive = slotMax - hubMax
        return preferNegative ? roomNegative : roomPositive
    }

    private static func contains(_ slot: LayoutRect, _ rect: LayoutRect) -> Bool {
        rect.minX >= slot.minX - 0.5 && rect.maxX <= slot.maxX + 0.5
            && rect.minY >= slot.minY - 0.5 && rect.maxY <= slot.maxY + 0.5
    }
}

/// A rectangle in a view's top-left coordinates. Foundation-only so the hinge
/// decision can run in unit tests without SwiftUI.
public struct LayoutRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }

    public var isUsable: Bool {
        x.isFinite && y.isFinite && width.isFinite && height.isFinite && width >= 0 && height >= 0
    }

    /// Edge contact does not count: a hub that ends exactly on the band is clear.
    public func intersects(_ other: LayoutRect) -> Bool {
        minX < other.maxX && maxX > other.minX && minY < other.maxY && maxY > other.minY
    }

    public func offsetBy(dx: Double, dy: Double) -> LayoutRect {
        LayoutRect(x: x + dx, y: y + dy, width: width, height: height)
    }
}

/// Translation, in points, applied to the wheel slot's contents.
public struct LayoutOffset: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = LayoutOffset(x: 0, y: 0)
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
/// `mrt://spin`: plays a spin already handed to `AppRouter` (no id in the URL).
/// `mrt://episodes`: opens the Episodes tab.
public enum DeepLink: Equatable, Sendable {
    case movie(id: String)
    case episode(guid: String)
    case spin
    case episodes

    public static let scheme = "mrt"

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let host = (components.host ?? "").lowercased()
        // Split the still-encoded path so an escaped "/" inside an id survives.
        let parts = components.percentEncodedPath.split(separator: "/").map(String.init)
        // mrt://movie/<id>  (also tolerate mrt:///movie/<id>)
        let segments = host.isEmpty ? parts : [host] + parts
        if segments.count == 1 {
            switch segments[0].lowercased() {
            case "spin": self = .spin
            case "episodes": self = .episodes
            default: return nil
            }
            return
        }
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
        switch self {
        case .spin: return Self.bare("spin")
        case .episodes: return Self.bare("episodes")
        case .movie(let movieID): return Self.identified("movie", movieID)
        case .episode(let guid): return Self.identified("episode", guid)
        }
    }

    private static func bare(_ host: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        return components.url ?? URL(string: "mrt://\(host)")!
    }

    private static func identified(_ host: String, _ id: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        components.percentEncodedPath = "/" + (id.addingPercentEncoding(withAllowedCharacters: allowed) ?? id)
        return components.url ?? URL(string: "mrt://\(host)")!
    }
}
