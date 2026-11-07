import Foundation
import ImageIO
import Synchronization

/// Loads images referenced by Markdown (`![alt](url)`) and custom emoji.
///
/// Provide your own to integrate an existing image pipeline, authenticated requests, or custom URL
/// schemes. Implementations must be thread-safe.
public protocol MarkdownImageLoader: Sendable {
    /// Loads and decodes the image at `url`, downsampled so its longest side is at most `maxPixelSize`.
    func loadImage(from url: URL, maxPixelSize: CGFloat) async throws -> MarkdownImage
    /// Returns an already decoded image synchronously, if available (avoids placeholder flashes when
    /// cells scroll back into view).
    func cachedImage(for url: URL, maxPixelSize: CGFloat) -> MarkdownImage?
    /// Pixel size of a previously loaded image, used to reserve exact space before loading.
    func knownPixelSize(for url: URL) -> CGSize?
}

extension MarkdownImageLoader {
    public func cachedImage(for url: URL, maxPixelSize: CGFloat) -> MarkdownImage? { nil }
    public func knownPixelSize(for url: URL) -> CGSize? { nil }
}

public enum MarkdownImageError: Error {
    case invalidResponse
    case undecodable
}

/// Default loader: `URLSession` with a disk `URLCache`, an in-memory cache of decoded images,
/// request de-duplication, and ImageIO decoding/downsampling off the main thread.
public final class DefaultMarkdownImageLoader: MarkdownImageLoader, @unchecked Sendable {
    public static let shared = DefaultMarkdownImageLoader()

    private struct Key: Hashable, Sendable {
        var url: URL
        var bucket: Int
    }

    private let session: URLSession
    private let memory = SendableCache<Key, MarkdownImage>(totalCostLimit: 96 << 20)
    private struct State {
        var inFlight: [Key: Task<MarkdownImage, Error>] = [:]
        var sizes: [URL: CGSize] = [:]
    }
    private let state = Mutex(State())

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.urlCache = URLCache(memoryCapacity: 8 << 20, diskCapacity: 256 << 20)
            configuration.requestCachePolicy = .returnCacheDataElseLoad
            self.session = URLSession(configuration: configuration)
        }
    }

    /// Rounds the requested size up to a power-of-two bucket so near-identical requests share entries.
    private static func bucket(_ maxPixelSize: CGFloat) -> Int {
        var bucket = 64
        while CGFloat(bucket) < maxPixelSize, bucket < 4096 { bucket *= 2 }
        return bucket
    }

    public func cachedImage(for url: URL, maxPixelSize: CGFloat) -> MarkdownImage? {
        memory[Key(url: url, bucket: Self.bucket(maxPixelSize))]
    }

    public func knownPixelSize(for url: URL) -> CGSize? {
        state.withLock { $0.sizes[url] }
    }

    public func loadImage(from url: URL, maxPixelSize: CGFloat) async throws -> MarkdownImage {
        let key = Key(url: url, bucket: Self.bucket(maxPixelSize))
        if let cached = memory[key] { return cached }
        let session = self.session
        let task = state.withLock { state -> Task<MarkdownImage, Error> in
            if let task = state.inFlight[key] { return task }
            let task = Task.detached(priority: .userInitiated) { () throws -> MarkdownImage in
                let data: Data
                if url.isFileURL {
                    data = try Data(contentsOf: url, options: .mappedIfSafe)
                } else {
                    let (body, response) = try await session.data(from: url)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        throw MarkdownImageError.invalidResponse
                    }
                    data = body
                }
                guard let image = MarkdownImage(data: data, maxPixelSize: CGFloat(key.bucket)) else {
                    throw MarkdownImageError.undecodable
                }
                return image
            }
            state.inFlight[key] = task
            return task
        }
        defer { state.withLock { _ = $0.inFlight.removeValue(forKey: key) } }
        let image = try await task.value
        let size = image.pixelSize
        let frames = image.isAnimated ? 4 : 1
        memory.set(image, for: key, cost: Int(size.width * size.height) * 4 * frames)
        state.withLock { $0.sizes[url] = size }
        return image
    }

    /// Clears decoded images (the disk cache is kept).
    public func removeAll() {
        memory.removeAll()
    }
}
