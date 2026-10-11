import SwiftUI

/// 1–5 stars. Tap a star to set; tap the current value again to clear.
/// Read-only when `onChange` is nil.
struct StarRatingView: View {
    let rating: Int?
    var font: Font = .title3
    var tint: Color = .orange
    var onChange: ((Int?) -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { star in
                let filled = star <= (rating ?? 0)
                if let onChange {
                    Button {
                        onChange(rating == star ? nil : star)
                    } label: {
                        starImage(filled: filled)
                    }
                    // Borderless so each star is its own tap target inside a List row.
                    .buttonStyle(.borderless)
                } else {
                    starImage(filled: filled)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rating")
        .accessibilityValue(rating.map { "\($0) of 5 stars" } ?? "Not rated")
        .accessibilityAdjustableAction { direction in
            guard let onChange else { return }
            let current = rating ?? 0
            switch direction {
            case .increment: onChange(min(current + 1, 5))
            case .decrement: onChange(current <= 1 ? nil : current - 1)
            @unknown default: break
            }
        }
    }

    private func starImage(filled: Bool) -> some View {
        Image(systemName: filled ? "star.fill" : "star")
            .font(font)
            .foregroundStyle(filled ? tint : Color.secondary.opacity(0.5))
            .contentShape(Rectangle())
    }
}

#Preview {
    VStack(spacing: 20) {
        StarRatingView(rating: 3, onChange: { _ in })
        StarRatingView(rating: nil, font: .caption)
    }
}
