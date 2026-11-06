import SwiftUI
import MRTCore
import MRTShared

/// 0.5…5 stars in half-star steps (values are half-stars, 1...10).
/// Tap a star's left half for ½, its right half for the whole star, or drag
/// across the row; tapping the current value again clears it. VoiceOver:
/// swipe up/down adjusts by ½ star. Read-only when `onChange` is nil.
/// When a rating is set, Clear rating removes it. The lowest star is still ½.
struct StarRatingView: View {
    let halfStars: Int?
    var font: Font = .title3
    var tint: Color = .orange
    var onChange: ((Int?) -> Void)?

    @State private var rowWidth: CGFloat = 0
    /// Live value while a finger is on the stars.
    @State private var dragValue: Int?
    @State private var dragMoved = false

    private var shown: Int? { dragValue ?? halfStars }
    private var canClear: Bool { onChange != nil && halfStars != nil }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            starRow
            if canClear {
                Button(RatingClearAction.title) {
                    onChange?(nil)
                }
                .buttonStyle(.bordered)
                .font(.subheadline)
                .accessibilityLabel(RatingClearAction.accessibilityLabel)
                .accessibilityHint(RatingClearAction.accessibilityHint)
                .accessibilityIdentifier(RatingClearAction.accessibilityIdentifier)
            }
        }
        // The row identifier lives on the caller. Containment has to be set
        // before that identifier or the Clear button is hidden from UI tests.
        .accessibilityElement(children: .contain)
    }

    private var starRow: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { star in
                starImage(fill: HalfStars.fill(star: star, halfStars: shown))
            }
        }
        .background {
            GeometryReader { g in
                Color.clear
                    .onAppear { rowWidth = g.size.width }
                    .onChange(of: g.size.width) { _, w in rowWidth = w }
            }
        }
        .contentShape(Rectangle())
        .gesture(onChange == nil ? nil : dragGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rating")
        .accessibilityValue(shown.map { "\(HalfStars.label($0)) of 5 stars" } ?? "Not rated")
        .accessibilityAdjustableAction { direction in
            guard let onChange else { return }
            switch direction {
            case .increment: onChange(HalfStars.adjusted(halfStars, increment: true))
            case .decrement: onChange(HalfStars.adjusted(halfStars, increment: false))
            @unknown default: break
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if abs(value.translation.width) > 6 { dragMoved = true }
                dragValue = HalfStars.fromLocation(Double(value.location.x), width: Double(rowWidth))
            }
            .onEnded { value in
                let picked = HalfStars.fromLocation(Double(value.location.x), width: Double(rowWidth))
                // A plain tap on the current value clears it (as before).
                let result: Int? = (!dragMoved && picked == halfStars) ? nil : picked
                dragValue = nil
                dragMoved = false
                onChange?(result)
            }
    }

    private func starImage(fill: Double) -> some View {
        Image(systemName: fill >= 1 ? "star.fill" : (fill > 0 ? "star.leadinghalf.filled" : "star"))
            .font(font)
            .foregroundStyle(fill > 0 ? tint : Color.secondary.opacity(0.5))
    }
}

#Preview {
    VStack(spacing: 20) {
        StarRatingView(halfStars: 7, onChange: { _ in })
        StarRatingView(halfStars: nil, font: .caption)
    }
}
