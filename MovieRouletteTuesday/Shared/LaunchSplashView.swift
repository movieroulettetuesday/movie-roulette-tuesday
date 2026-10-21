import SwiftUI
import UIKit
import Observation
import MRTCore

/// Cold-launch opening animation (see `LaunchSplash` for the geometry/curves).
///
/// One instance per process, created in the App, so it only ever plays on a
/// cold launch, never when returning from the background. It is a pure
/// overlay: data loading starts in ContentView's own tasks regardless and is
/// never awaited here. A tap, a deep link or a widget open finishes it at once.
@MainActor
@Observable
final class SplashState {
    /// 0 = the launch-screen frame, 1 = the real screen. Changed only inside
    /// `withAnimation`, so views read the target and SwiftUI interpolates.
    private(set) var progress: Double
    /// The cover is removed once the animation completes (or on skip).
    private(set) var isFinished: Bool
    /// Wheel hub (untransformed) in window coordinates, reported by RouletteView.
    private(set) var hubCenter: CGPoint?
    private(set) var hubSize: CGFloat?
    /// Fixed for the whole opening so cover and wheel agree.
    let reduceMotion: Bool
    /// The storyboard follows the *system* appearance, not Settings → Appearance
    /// (a window override), so the cover does too; it then fades into the app.
    private(set) var launchScheme: ColorScheme?
    @ObservationIgnored private var started = false

    init(enabled: Bool = true, reduceMotion: Bool? = nil) {
        progress = enabled ? 0 : 1
        isFinished = !enabled
        self.reduceMotion = reduceMotion ?? UIAccessibility.isReduceMotionEnabled
    }

    var isActive: Bool { !isFinished }

    func reportHub(center: CGPoint, size: CGFloat) {
        guard isActive, progress == 0, center != hubCenter || size != hubSize else { return }
        hubCenter = center
        hubSize = size
    }

    func captureLaunchScheme(from scene: UIWindowScene?) {
        guard launchScheme == nil, let style = scene?.screen.traitCollection.userInterfaceStyle else { return }
        launchScheme = style == .dark ? .dark : .light
    }

    /// Waits (at most `maxWaitForHub`) for the wheel's first layout so the badge
    /// knows where to land, then plays the 0.5 s opening.
    func play(hold: Double = 0) async {
        guard !started, isActive else { return }
        started = true
        if hold > 0 { try? await Task.sleep(for: .seconds(hold)) }
        let deadline = ContinuousClock.now + .seconds(LaunchSplash.maxWaitForHub)
        while hubCenter == nil, isActive, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(16))
        }
        guard isActive, progress == 0 else { return }
        let curve: Animation = reduceMotion
            ? .easeInOut(duration: LaunchSplash.duration)
            : .timingCurve(0.215, 0.61, 0.355, 1, duration: LaunchSplash.duration)   // easeOutCubic
        withAnimation(curve) { progress = 1 } completion: { [weak self] in self?.isFinished = true }
    }

    /// Tap / deep link / widget: finish now (quick fade; never lands behind it).
    func skip() {
        guard isActive else { return }
        withAnimation(.easeOut(duration: LaunchSplash.skipDuration)) {
            progress = 1
            isFinished = true
        }
    }
}

/// Full-window cover: exactly the storyboard's gradient + badge on its first
/// frame; the badge then glides/shrinks into the hub as the gradient fades.
struct SplashCover: View {
    let state: SplashState
    @Environment(\.colorScheme) private var appScheme

    var body: some View {
        GeometryReader { geo in
            let w = Double(geo.size.width), h = Double(geo.size.height)
            let p = state.progress
            let hubKnown = state.hubCenter != nil
            let reduce = state.reduceMotion || !hubKnown
            let startD = LaunchSplash.badgeDiameter(windowWidth: w)
            let start = LaunchSplash.badgeCenter(windowWidth: w, windowHeight: h)
            let hub = state.hubCenter.map { (x: Double($0.x), y: Double($0.y)) } ?? start
            let d = LaunchSplash.badgeDiameter(progress: p, start: startD, hub: Double(state.hubSize ?? startD), reduceMotion: reduce)
            let c = LaunchSplash.badgeCenter(progress: p, start: start, hub: hub, reduceMotion: reduce)
            let image = d / LaunchSplash.badgeImageDiscFraction
            ZStack {
                Image("LaunchGradient")
                    .resizable()
                    .opacity(LaunchSplash.coverOpacity(progress: p))
                Image("LaunchBadge")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: image, height: image)
                    .position(x: c.x, y: c.y)
                    .opacity(LaunchSplash.badgeOpacity(progress: p, reduceMotion: reduce))
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .environment(\.colorScheme, state.launchScheme ?? appScheme)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { state.skip() }
        .accessibilityHidden(true)
        .transition(.opacity)
    }
}

/// Wheel-side transforms for the opening; removed entirely once finished (or
/// without a splash).
///
/// Removal is structural on purpose: if the window's geometry changes while
/// the opening runs (iPad rotation, Split View / Stage Manager resize), the
/// wheel's final look never depends on how an interrupted animation ended;
/// dropping the effect when the splash finishes rebuilds it at rest.
struct SplashWheelEffect: ViewModifier {
    let state: SplashState?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let state, state.isActive {
            let p = state.progress
            let reduce = state.reduceMotion
            content
                .scaleEffect(LaunchSplash.wheelScale(progress: p, reduceMotion: reduce))
                .rotationEffect(.degrees(LaunchSplash.wheelRotationDegrees(progress: p, reduceMotion: reduce)))
                .opacity(LaunchSplash.wheelOpacity(progress: p))
                .transition(.identity)
        } else {
            content
                .transition(.identity)
        }
    }
}
