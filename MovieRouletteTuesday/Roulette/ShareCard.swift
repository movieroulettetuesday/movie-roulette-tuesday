import SwiftUI

/// Branded result card, rendered to an image with `ImageRenderer` and shared
/// via `ShareLink`. Fixed 4:5 layout (1080×1350 px at scale 3).
struct ShareCardView: View {
    let title: String
    let year: Int
    let categoryName: String
    let categoryHex: String
    let episodeText: String
    var isJackpot = false

    static let size = CGSize(width: 360, height: 450)

    private var ink: Color { isJackpot ? .white : Color(hex: "#14181A") }
    private var secondaryInk: Color { isJackpot ? .white.opacity(0.75) : Color(hex: "#14181A").opacity(0.65) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 12)
            VStack(spacing: 12) {
                Text(isJackpot ? "💀 INFAMOUS JACKPOT 💀" : "TONIGHT'S SPIN")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(isJackpot ? Brand.jackpotGold : Color(hex: CleanProColors.headingLight))
                Text(title)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(isJackpot ? Brand.jackpotGold : ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.5)
                Text(verbatim: "\(year)")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(secondaryInk)
                Text(categoryName.uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Color.labelColor(onHex: categoryHex))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(hex: categoryHex), in: Capsule())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .padding(.horizontal, 16)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isJackpot ? Color(hex: "#1C2427") : .white)
                    .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                    .shadow(color: .black.opacity(0.08), radius: 14, y: 8)
            }
            Spacer(minLength: 12)
            Label(episodeText, systemImage: "mic.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: "#14181A"))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(colors: [Color(hex: CleanProColors.peach), Color(hex: "#F9D3AE")],
                                   startPoint: .leading, endPoint: .trailing),
                    in: Capsule()
                )
            Text("Spun in the Movie Roulette Tuesday app")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(secondaryInk)
                .padding(.top, 10)
        }
        .padding(24)
        .frame(width: Self.size.width, height: Self.size.height)
        .background {
            LinearGradient(
                colors: (isJackpot ? CleanProColors.backgroundDark : CleanProColors.backgroundLight).map { Color(hex: $0) },
                startPoint: .top, endPoint: .bottom
            )
        }
        .overlay {
            if isJackpot {
                RoundedRectangle(cornerRadius: 0).strokeBorder(Brand.jackpotGold, lineWidth: 6)
            }
        }
        .environment(\.colorScheme, isJackpot ? .dark : .light)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            VStack(alignment: .leading, spacing: 0) {
                Text("Movie Roulette")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(ink)
                Text("Tuesday")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(isJackpot ? Color(hex: CleanProColors.peach) : Color(hex: CleanProColors.headingLight))
            }
            Spacer()
        }
    }
}

@MainActor
enum ShareCardRenderer {
    static func image(for reveal: RouletteViewModel.Reveal, episodeText: String) -> Image? {
        let card = ShareCardView(
            title: reveal.movie.title,
            year: reveal.movie.year,
            categoryName: reveal.category.displayName,
            categoryHex: reveal.category.displayHex,
            episodeText: episodeText,
            isJackpot: reveal.isJackpot
        )
        // Fixed branded look: same image whether the app is in light or dark mode
        // (ShareCardView pins its own color scheme).
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(ShareCardView.size)
        guard let uiImage = renderer.uiImage else { return nil }
        return Image(uiImage: uiImage)
    }
}

#Preview {
    ShareCardView(
        title: "The Outsiders", year: 1983, categoryName: "Listener Picks", categoryHex: "#5E7DC0",
        episodeText: "Discussed on The Outsiders (S4E34)"
    )
}
