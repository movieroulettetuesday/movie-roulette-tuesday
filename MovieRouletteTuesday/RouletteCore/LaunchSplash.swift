import Foundation

/// The cold-launch opening: LaunchScreen.storyboard shows the Clean Pro
/// gradient with the film-reel badge; on the first frame the SwiftUI cover
/// draws the very same badge at the very same place, then (0.5 s) glides and
/// shrinks it into the wheel hub while the wheel fades/scales in with a small
/// 24-degree settle. Reduce Motion: a plain crossfade, nothing moves.
///
/// The storyboard can't know where the hub is (it differs per device and
/// orientation), so it uses this fixed, window-relative position, and the
/// cover animates from here to the measured hub. The storyboard constraints
/// mirror these constants; `LaunchSplashTests` keeps them in step.
public enum LaunchSplash {
    /// Opening animation length.
    public static let duration = 0.5
    /// Badge diameter on the launch screen: 30% of the window width, at most 280 pt.
    public static let badgeWidthFraction = 0.3
    public static let badgeMaxDiameter = 280.0
    /// LaunchBadge.png is 1000 px with the disc 760 px across (shadows use the rest).
    public static let badgeImageDiscFraction = 0.76
    /// Badge centre: horizontally centred, at 1.09 x the window's centre height
    /// (storyboard: centerY multiplier). Measured hubs: iPhone 18 Pro 477/437 =
    /// 1.092, iPad 13" portrait 752/688 = 1.093, SE 352/333.5 = 1.055, so the
    /// badge only travels a few points into the hub on most devices.
    public static let badgeCenterYFactor = 1.09
    /// Never hold the launch frame longer than this waiting for the wheel's
    /// first layout; after it the cover just crossfades (data keeps loading).
    public static let maxWaitForHub = 0.6
    /// A tap, deep link or widget open finishes the opening this fast.
    public static let skipDuration = 0.12

    // MARK: Storyboard geometry

    public static func badgeDiameter(windowWidth: Double) -> Double {
        min(sane(windowWidth) * badgeWidthFraction, badgeMaxDiameter)
    }

    public static func badgeCenter(windowWidth: Double, windowHeight: Double) -> (x: Double, y: Double) {
        (sane(windowWidth) / 2, sane(windowHeight) / 2 * badgeCenterYFactor)
    }

    /// Storyboard image-view width multiplier / cap (the PNG includes shadow padding).
    public static var storyboardWidthMultiplier: Double { badgeWidthFraction / badgeImageDiscFraction }
    public static var storyboardMaxImageWidth: Double { badgeMaxDiameter / badgeImageDiscFraction }

    // MARK: Animation curves (progress 0 = launch frame, 1 = finished)

    /// The cover (gradient) fades out as the wheel appears.
    public static func coverOpacity(progress p: Double) -> Double { 1 - clamp(p) }

    /// Badge: glides start -> hub and shrinks/grows to the hub size; Reduce
    /// Motion keeps it still and fades it instead.
    public static func badgeDiameter(progress p: Double, start: Double, hub: Double, reduceMotion: Bool) -> Double {
        reduceMotion ? start : lerp(start, hub, clamp(p))
    }

    public static func badgeCenter(progress p: Double, start: (x: Double, y: Double), hub: (x: Double, y: Double),
                                   reduceMotion: Bool) -> (x: Double, y: Double) {
        if reduceMotion { return start }
        let t = clamp(p)
        return (lerp(start.x, hub.x, t), lerp(start.y, hub.y, t))
    }

    public static func badgeOpacity(progress p: Double, reduceMotion: Bool) -> Double {
        reduceMotion ? 1 - clamp(p) : 1
    }

    /// Wheel: scale 0.82 -> 1 and rotation -24 -> 0 degrees; fades in over the first ~60%.
    public static func wheelScale(progress p: Double, reduceMotion: Bool) -> Double {
        reduceMotion ? 1 : 0.82 + 0.18 * clamp(p)
    }

    public static func wheelRotationDegrees(progress p: Double, reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : -24 * (1 - clamp(p))
    }

    public static func wheelOpacity(progress p: Double) -> Double { min(1, clamp(p) * 1.6) }

    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    private static func clamp(_ p: Double) -> Double { p.isFinite ? min(max(p, 0), 1) : 1 }
    private static func sane(_ v: Double) -> Double { v.isFinite ? max(0, v) : 0 }
}
