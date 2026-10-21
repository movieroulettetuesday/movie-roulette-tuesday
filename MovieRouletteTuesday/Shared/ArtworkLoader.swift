import ImageIO
import UIKit
import MRTCore

/// Loads podcast artwork (app only; the widget never loads images).
///
/// - Network: a dedicated URLSession with its own bounded URLCache
///   (8 MB memory / 150 MB disk under Caches/Artwork). Requests use
///   `.returnCacheDataElseLoad`: Buzzsprout image URLs change whenever the
///   art changes, so a cached copy is always valid and works offline.
/// - Decode: ImageIO thumbnailing straight to the displayed pixel size, off the
///   main actor; the full 1400 px image is never decoded.
/// - Memory: decoded images live in an NSCache bounded by bytes (32 MB) and
///   count; it is purged on memory warnings.
/// - Cancellation: each caller awaits in its own (structured) task, so a row
///   that scrolls away cancels its download/decode.
final class ArtworkLoader: @unchecked Sendable {
    // @unchecked: only immutable lets of thread-safe types (URLSession, NSCache).
    static let shared = ArtworkLoader()

    static let memoryCostLimit = 32 << 20
    static let memoryCountLimit = 300
    static let maxDownloadBytes = 15 << 20

    /// NSCache is internally synchronized; boxed so the memory-warning
    /// handler can capture it under strict concurrency checking.
    private final class DecodedCache: @unchecked Sendable {
        let storage = NSCache<NSString, UIImage>()
    }

    private let session: URLSession
    private let decodedBox = DecodedCache()
    private var decoded: NSCache<NSString, UIImage> { decodedBox.storage }
    private let memoryWarningObserver: NSObjectProtocol

    init(directoryName: String = "Artwork") {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(directoryName, isDirectory: true)
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 8 << 20, diskCapacity: 150 << 20, directory: directory)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 20
        config.httpMaximumConnectionsPerHost = 4
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
        decodedBox.storage.totalCostLimit = Self.memoryCostLimit
        decodedBox.storage.countLimit = Self.memoryCountLimit
        let box = decodedBox
        // Raw name of UIApplication.didReceiveMemoryWarningNotification, so this
        // nonisolated init doesn't touch a main-actor UIKit symbol.
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("UIApplicationDidReceiveMemoryWarningNotification"), object: nil, queue: nil
        ) { _ in box.storage.removeAllObjects() }
    }

    deinit {
        NotificationCenter.default.removeObserver(memoryWarningObserver)
        session.invalidateAndCancel()
    }

    private static func key(_ url: URL, _ maxPixel: Int) -> NSString {
        "\(maxPixel)|\(url.absoluteString)" as NSString
    }

    /// Already-decoded image for the first (preferred) URL, for drawing a
    /// cached thumbnail on the first frame without a placeholder flash.
    func cachedImage(for urls: [URL], maxPixel: Int) -> UIImage? {
        guard let first = urls.first else { return nil }
        return decoded.object(forKey: Self.key(first, maxPixel))
    }

    /// First URL that downloads (or comes from cache) and decodes, best first.
    /// nil when all fail or the task was cancelled -> caller shows a placeholder.
    @concurrent
    func image(for urls: [URL], maxPixel: Int) async -> UIImage? {
        for url in urls {
            if Task.isCancelled { return nil }
            let key = Self.key(url, maxPixel)
            if let hit = decoded.object(forKey: key) { return hit }
            guard let data = try? await download(url) else { continue }
            if Task.isCancelled { return nil }
            guard let image = Self.downsample(data, maxPixel: maxPixel) else { continue }
            decoded.setObject(image, forKey: key, cost: Self.cost(of: image))
            return image
        }
        return nil
    }

    private func download(_ url: URL) async throws -> Data {
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              !data.isEmpty, data.count <= Self.maxDownloadBytes else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    /// ImageIO thumbnail at `maxPixel` on the longest side, decoded now (so
    /// scrolling never decodes on the main thread) and never at full size.
    static func downsample(_ data: Data, maxPixel: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(ArtworkSizing.minPixels, maxPixel),
        ] as [CFString: Any] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private static func cost(of image: UIImage) -> Int {
        guard let cg = image.cgImage else { return 1 }
        return max(1, cg.bytesPerRow * cg.height)
    }
}
