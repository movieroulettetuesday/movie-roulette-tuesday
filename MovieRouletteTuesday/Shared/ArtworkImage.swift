import SwiftUI

/// Square podcast artwork that tries `urls` in order (episode art, then show
/// art) and shows a placeholder until one loads or when none does. Decodes
/// at the size it's drawn (`pointSize`), so list thumbnails stay small.
struct ArtworkImage: View {
    let urls: [URL]
    let pointSize: CGFloat
    var cornerRadius: CGFloat = 8
    var placeholderSymbol = "film"
    /// Off for decorative uses (blurred backdrop): nothing until art loads.
    var showsPlaceholder = true

    @Environment(\.displayScale) private var displayScale
    @State private var loaded: Loaded?

    private struct Key: Hashable {
        let urls: [URL]
        let maxPixel: Int
    }

    private struct Loaded {
        let key: Key
        let image: UIImage
    }

    private var key: Key {
        Key(urls: urls, maxPixel: ArtworkSizing.maxPixelSize(points: Double(pointSize), scale: Double(displayScale)))
    }

    var body: some View {
        let key = self.key
        let image = (loaded?.key == key ? loaded?.image : nil)
            ?? ArtworkLoader.shared.cachedImage(for: key.urls, maxPixel: key.maxPixel)
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if showsPlaceholder {
                Rectangle().fill(.quaternary)
                Image(systemName: placeholderSymbol)
                    .font(.system(size: max(12, pointSize * 0.3)))
                    .foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: key) {
            // Structured: cancelled when the view disappears (e.g. scrolled off).
            if loaded?.key == key { return }
            if ArtworkLoader.shared.cachedImage(for: key.urls, maxPixel: key.maxPixel) != nil { return }
            guard !key.urls.isEmpty else { return }
            let result = await ArtworkLoader.shared.image(for: key.urls, maxPixel: key.maxPixel)
            guard !Task.isCancelled, let result else { return }
            loaded = Loaded(key: key, image: result)
        }
        .accessibilityHidden(true)
    }
}
