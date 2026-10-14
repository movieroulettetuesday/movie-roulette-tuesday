import SwiftUI

/// The wheel, Clean Pro style. Only the face (segments + labels) rotates; the
/// rim, its shadow and the film-badge hub are static layers, so a spin only
/// re-composites one rotating layer. Slice angles come from `WheelGeometry`,
/// the same value used to compute the winner.
struct WheelView: View {
    let categories: [RouletteCategory]
    let geometry: WheelGeometry
    /// Degrees; applied to the face only (render-only transform, no relayout).
    var rotation: Double = 0
    /// Static extra rotation while a stopped spin decelerates (see SpinStopPlan).
    var stopOffset: Double = 0

    @Environment(\.colorScheme) private var scheme

    static func rimWidth(for diameter: CGFloat) -> CGFloat { max(6, diameter * 0.022) }

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)
            let rim = Self.rimWidth(for: diameter)
            ZStack {
                // Static: soft layered shadow under the wheel.
                Circle()
                    .fill(CleanPro.cardFill)
                    .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.10), radius: 4, y: 2)
                    .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.14), radius: 18, y: 10)

                // Rotating: segments + labels.
                ZStack {
                    WheelFace(categories: categories, geometry: geometry, separator: separator)
                        .equatable()
                    labels(diameter: diameter, rim: rim)
                }
                .frame(width: diameter - rim * 2, height: diameter - rim * 2)
                .rotationEffect(.degrees(rotation))
                // Tap-to-stop offset: a separate, never-animated rotation, so
                // changing it doesn't touch the running spin animation.
                .rotationEffect(.degrees(stopOffset))

                // Static: rim and hub.
                Circle()
                    .strokeBorder(
                        AngularGradient(colors: (scheme == .dark ? CleanProColors.rimDark : CleanProColors.rimLight).map { Color(hex: $0) },
                                        center: .center),
                        lineWidth: rim
                    )
                hub(diameter: diameter)
            }
            .frame(width: diameter, height: diameter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var separator: Color {
        scheme == .dark ? .black.opacity(0.25) : .white.opacity(0.85)
    }

    private func labels(diameter: CGFloat, rim: CGFloat) -> some View {
        let faceRadius = diameter / 2 - rim
        let labelRadius = faceRadius * 0.64
        // Fixed size from the diameter (not Dynamic Type): it must fit the
        // slice and never changes while spinning.
        let fontSize = max(10, diameter * 0.04)

        return ForEach(geometry.segments) { segment in
            if categories.indices.contains(segment.index) {
                let category = categories[segment.index]
                Text(category.name)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(Color.labelColor(onHex: category.displayHex))
                    .multilineTextAlignment(.center)
                    // One word never breaks mid-word: it shrinks to fit instead.
                    .lineLimit(category.name.contains(" ") ? 2 : 1)
                    .minimumScaleFactor(0.6)
                    .frame(width: labelWidth(for: segment, at: labelRadius, faceRadius: faceRadius))
                    // Offset first, then rotate about the wheel center.
                    .offset(y: -labelRadius)
                    .rotationEffect(.degrees(segment.midAngle))
                    .accessibilityHidden(true)
            }
        }
    }

    /// Chord across the slice at the label radius, capped to stay inside the face.
    private func labelWidth(for segment: WheelGeometry.Segment, at radius: CGFloat, faceRadius: CGFloat) -> CGFloat {
        let halfSweep = min(segment.sweep, 180) / 2 * .pi / 180
        let chord = 2 * radius * CGFloat(sin(halfSweep))
        return max(24, min(chord * 0.92, faceRadius * 0.75))
    }

    /// Film-badge hub: card-colored disc, hairline peach ring, teal reel with a
    /// peach frame, one layered shadow.
    private func hub(diameter: CGFloat) -> some View {
        let size = diameter * 0.23
        return ZStack {
            Circle()
                .fill(Color(hex: scheme == .dark ? CleanProColors.hubDiscDark : CleanProColors.hubDiscLight))
            Circle()
                .strokeBorder(Color(hex: CleanProColors.peach).opacity(scheme == .dark ? 0.7 : 0.9), lineWidth: 1.5)
                .padding(size * 0.06)
            FilmBadge(size: size * 0.5)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.08), radius: 2, y: 1)
        .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.14), radius: 12, y: 5)
        .accessibilityHidden(true)
    }
}

/// Segments with a gentle radial gradient each. Drawn once per category/size
/// change; spinning rotates the already-rendered layer.
private struct WheelFace: View, Equatable {
    let categories: [RouletteCategory]
    let geometry: WheelGeometry
    let separator: Color

    var body: some View {
        let stops = categories.map { CategoryPalette.radialStops($0.displayHex).map { Color(hex: $0) } }
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for segment in geometry.segments {
                let colors = stops.indices.contains(segment.index) ? stops[segment.index] : [.gray, .gray, .gray]
                var wedge = Path()
                wedge.move(to: center)
                // Geometry angles are clockwise from 12 o'clock. Path angles start at
                // 3 o'clock and, in SwiftUI's y-down space, increase clockwise: hence -90.
                wedge.addRelativeArc(
                    center: center,
                    radius: radius,
                    startAngle: .degrees(segment.startAngle - 90),
                    delta: .degrees(segment.sweep)
                )
                wedge.closeSubpath()
                context.fill(wedge, with: .radialGradient(
                    Gradient(colors: colors), center: center, startRadius: radius * 0.15, endRadius: radius
                ))
                context.stroke(wedge, with: .color(separator), lineWidth: 2)
            }
        }
    }
}

/// Fixed arrow at 12 o'clock, pointing down into the wheel (rounded corners).
struct WheelPointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path.strokedPath(StrokeStyle(lineWidth: 4, lineJoin: .round)).union(path)
    }
}

#Preview {
    WheelView(
        categories: [
            RouletteCategory(id: "cat-horror", name: "Horror", colorHex: "#C1121F"),
            RouletteCategory(id: "cat-cult", name: "Cult", colorHex: "#7B2CBF"),
            RouletteCategory(id: "cat-criterion", name: "Criterion", colorHex: "#E9C46A"),
            RouletteCategory(id: "cat-new", name: "New Theme", colorHex: "#FF5D8F"),
        ],
        geometry: WheelGeometry(segmentCount: 4)
    )
    .padding(40)
}
