import SwiftUI
import MRTCore

/// The wheel hub is the spin button (no SPIN pill): a teal-to-peach glow ring
/// says "tap me", pressing dims/shrinks it. It sits over WheelView's static hub
/// and is its own accessibility element ("Spin", a Button, dimmed while the
/// wheel spins), separate from the combined "Roulette wheel" element, so
/// VoiceOver, Voice Control ("Tap Spin") and Full Keyboard Access all reach it.
struct HubSpinButton: View {
    let hubSize: CGFloat
    let enabled: Bool
    /// While spinning: a ■ stop button sits on the hub (the Spin button stays
    /// there, dimmed, as before).
    var canStop: Bool = false
    var onStop: () -> Void = {}
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Button(action: action) {
                Color.clear.frame(width: hubSize, height: hubSize)
            }
            .buttonStyle(HubSpinButtonStyle(hubSize: hubSize, dark: scheme == .dark, forcedPressed: Self.forcedPressed))
            .disabled(!enabled)
            .accessibilityLabel("Spin")
            .accessibilityHint("Spins the wheel")
            .accessibilityInputLabels(["Spin", "Spin the wheel", "Spin wheel"])
            .accessibilityIdentifier("hub-spin-button")

            if canStop {
                Button(action: onStop) {
                    HubStopFace(hubSize: hubSize, dark: scheme == .dark)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
                .accessibilityLabel("Stop")
                .accessibilityHint("Stops the wheel early on a random slice")
                .accessibilityInputLabels(["Stop", "Stop the wheel", "Stop spin"])
                .accessibilityIdentifier("hub-stop-button")
            }
        }
        .animation(.easeInOut(duration: 0.15), value: canStop)
    }

    private static var forcedPressed: Bool {
        #if DEBUG
        DebugLaunch.hubPressed
        #else
        false
        #endif
    }
}

/// ■ on a teal disc over the hub (approved Oct 14 mockup).
private struct HubStopFace: View {
    let hubSize: CGFloat
    let dark: Bool

    var body: some View {
        let teal = Color(hex: dark ? CleanProColors.hubTealDark : CleanProColors.hubTealLight)
        ZStack {
            Circle().fill(.white)
            Circle().strokeBorder(Color(hex: CleanProColors.peach), lineWidth: max(2, hubSize * 0.03))
            Circle().fill(teal).padding(hubSize * 0.12)
            RoundedRectangle(cornerRadius: hubSize * 0.03)
                .fill(.white)
                .frame(width: hubSize * 0.26, height: hubSize * 0.26)
        }
        .frame(width: hubSize, height: hubSize)
        .contentShape(Circle())
    }
}

private struct HubSpinButtonStyle: ButtonStyle {
    let hubSize: CGFloat
    let dark: Bool
    let forcedPressed: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed || forcedPressed
        let teal = Color(hex: dark ? CleanProColors.hubTealDark : CleanProColors.hubTealLight)
        let ring = max(3, hubSize * 0.035)
        return ZStack {
            // Glow + gradient ring just outside the hub. Dimmed (not hidden) while spinning.
            Circle()
                .stroke(
                    AngularGradient(colors: [teal, Color(hex: CleanProColors.peach), teal], center: .center),
                    lineWidth: pressed ? ring + 1 : ring
                )
                .frame(width: hubSize + 10, height: hubSize + 10)
                .shadow(color: teal.opacity(pressed ? 0.85 : (isEnabled ? 0.55 : 0.2)), radius: pressed ? 16 : 10)
                .opacity(isEnabled ? 1 : 0.45)
            if pressed {
                Circle()
                    .fill(teal.opacity(dark ? 0.22 : 0.14))
                    .frame(width: hubSize, height: hubSize)
            }
            configuration.label
        }
        .scaleEffect(pressed ? 0.94 : 1)
        .contentShape(Circle())
        .animation(.spring(duration: 0.2), value: configuration.isPressed)
        .animation(.easeInOut(duration: 0.2), value: isEnabled)
    }
}
