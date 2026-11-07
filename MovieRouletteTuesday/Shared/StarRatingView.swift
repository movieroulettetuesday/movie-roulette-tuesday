import SwiftUI

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
        ZStack {
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { star in
                    starImage(fill: HalfStars.fill(star: star, halfStars: shown))
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            // Ten half-star targets. A tap uses the button, not a normalized
            // coordinate: on a 3x iPhone, XCTest reports this row at about 1/3
            // of its point size, so coordinate(withNormalizedOffset:) misses it.
            HStack(spacing: 0) {
                ForEach(1...10, id: \.self) { step in
                    Button {
                        select(step)
                    } label: {
                        Rectangle()
                            .fill(Color.white.opacity(0.001))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("rating-step-\(step)")
                    .accessibilityLabel("\(HalfStars.label(step)) of 5 stars")
                }
            }
            .background {
                GeometryReader { g in
                    Color.clear
                        .onAppear { rowWidth = g.size.width }
                        .onChange(of: g.size.width) { _, w in rowWidth = w }
                }
            }
            .simultaneousGestureIf(onChange != nil, dragGesture)
            .allowsHitTesting(onChange != nil)
            .accessibilityHidden(onChange == nil)
        }
        .accessibilityElement(children: .contain)
        .overlay {
            // VoiceOver still adjusts the whole row by half a star. It does not
            // take touches; the half-step buttons do.
            Color.clear
                .frame(maxWidth: .infinity, minHeight: 44)
                .allowsHitTesting(false)
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
    }

    /// Tap the current half-step again to clear it. A drag that already chose
    /// a value must not also fire the button underneath the finger.
    private func select(_ step: Int) {
        if dragMoved {
            dragMoved = false
            return
        }
        onChange?(step == halfStars ? nil : step)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard rowWidth > 0 else { return }
                if abs(value.translation.width) > 6 { dragMoved = true }
                dragValue = HalfStars.fromLocation(Double(value.location.x), width: Double(rowWidth))
            }
            .onEnded { value in
                guard rowWidth > 0 else {
                    dragValue = nil
                    dragMoved = false
                    return
                }
                let picked = HalfStars.fromLocation(Double(value.location.x), width: Double(rowWidth))
                let moved = dragMoved
                dragValue = nil
                dragMoved = false
                guard moved else { return }
                onChange?(picked)
            }
    }

    private func starImage(fill: Double) -> some View {
        Image(systemName: fill >= 1 ? "star.fill" : (fill > 0 ? "star.leadinghalf.filled" : "star"))
            .font(font)
            .foregroundStyle(fill > 0 ? tint : Color.secondary.opacity(0.5))
    }
}

private extension View {
    @ViewBuilder
    func simultaneousGestureIf<G: Gesture>(_ enabled: Bool, _ gesture: G) -> some View {
        if enabled {
            self.simultaneousGesture(gesture)
        } else {
            self
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        StarRatingView(halfStars: 7, onChange: { _ in })
        StarRatingView(halfStars: nil, font: .caption)
    }
}
