import QuartzCore
import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// A decoded image for Markdown rendering: static or animated (GIF, APNG, WebP, HEICS).
public struct MarkdownImage: Sendable {
    enum Content: Sendable {
        case still(SendableImage)
        case animated(AnimatedImage)
    }

    let content: Content

    /// Size in pixels.
    public var pixelSize: CGSize {
        switch content {
        case .still(let image): CGSize(width: image.cgImage.width, height: image.cgImage.height)
        case .animated(let animation): animation.pixelSize
        }
    }

    public var isAnimated: Bool {
        if case .animated = content { return true }
        return false
    }

    /// First (or only) frame.
    var firstFrame: CGImage {
        switch content {
        case .still(let image): image.cgImage
        case .animated(let animation): animation.frame(at: 0)
        }
    }

    public init(cgImage: CGImage) {
        content = .still(SendableImage(cgImage: cgImage, scale: 1))
    }

    /// Decodes image data (any ImageIO format), downsampling so the longest side is at most
    /// `maxPixelSize`. Multi-frame images become animated.
    public init?(data: Data, maxPixelSize: CGFloat = 2048) {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        self.init(source: source, maxPixelSize: maxPixelSize)
    }

    init?(source: CGImageSource, maxPixelSize: CGFloat) {
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }
        if count > 1, let animation = AnimatedImage(source: source, maxPixelSize: maxPixelSize) {
            content = .animated(animation)
        } else if let image = ImageDecoding.thumbnail(source, index: 0, maxPixelSize: maxPixelSize) {
            content = .still(SendableImage(cgImage: image, scale: 1))
        } else {
            return nil
        }
    }
}

enum ImageDecoding {
    /// Decodes frame `index`, downsampled, fully decoded (so drawing doesn't decode on the main thread).
    static func thumbnail(_ source: CGImageSource, index: Int, maxPixelSize: CGFloat) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maxPixelSize)),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary)
    }
}

/// A multi-frame image with per-frame delays. Frames are decoded up front when they fit in a memory
/// budget, otherwise decoded on demand with a small cache.
final class AnimatedImage: @unchecked Sendable {
    let frameCount: Int
    let delays: [TimeInterval]
    let duration: TimeInterval
    let pixelSize: CGSize
    /// Shortest frame delay; drives the redraw interval.
    let minimumDelay: TimeInterval

    private let source: CGImageSource
    private let maxPixelSize: CGFloat
    private let cumulative: [TimeInterval]
    private let lock = NSLock()
    private var frames: [CGImage?]
    private let keepsAllFrames: Bool
    private var recentlyUsed: [Int] = []

    static let preDecodeBudget = 24 << 20 // bytes

    init?(source: CGImageSource, maxPixelSize: CGFloat) {
        let count = CGImageSourceGetCount(source)
        guard count > 1, let first = ImageDecoding.thumbnail(source, index: 0, maxPixelSize: maxPixelSize) else { return nil }
        self.source = source
        self.maxPixelSize = maxPixelSize
        frameCount = count
        pixelSize = CGSize(width: first.width, height: first.height)

        var delays: [TimeInterval] = []
        delays.reserveCapacity(count)
        for index in 0..<count {
            delays.append(Self.delay(source, index: index))
        }
        self.delays = delays
        var total: TimeInterval = 0
        cumulative = delays.map { total += $0; return total }
        duration = total
        minimumDelay = delays.min() ?? 0.1

        let frameBytes = first.bytesPerRow * first.height
        keepsAllFrames = frameBytes * count <= Self.preDecodeBudget
        frames = Array(repeating: nil, count: count)
        frames[0] = first
        if keepsAllFrames {
            for index in 1..<count {
                frames[index] = ImageDecoding.thumbnail(source, index: index, maxPixelSize: maxPixelSize)
            }
        }
    }

    func frameIndex(at time: TimeInterval) -> Int {
        guard duration > 0 else { return 0 }
        let t = time.truncatingRemainder(dividingBy: duration)
        var low = 0, high = cumulative.count - 1
        while low < high {
            let mid = (low + high) / 2
            if cumulative[mid] <= t { low = mid + 1 } else { high = mid }
        }
        return low
    }

    /// Every decoded frame, when the whole animation fits the pre-decode budget.
    var allFrames: [CGImage]? {
        guard keepsAllFrames else { return nil }
        lock.lock(); defer { lock.unlock() }
        let decoded = frames.compactMap { $0 }
        return decoded.count == frameCount ? decoded : nil
    }

    /// Keyframe animation of the frames on a layer's `contents`, played by Core Animation (no work on
    /// the main thread per frame). `nil` for animations too large to keep in memory.
    func makeContentsAnimation() -> CAKeyframeAnimation? {
        guard duration > 0, let frames = allFrames else { return nil }
        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = frames
        var keyTimes: [NSNumber] = [0]
        for value in cumulative.dropLast() { keyTimes.append(NSNumber(value: value / duration)) }
        keyTimes.append(1)
        animation.keyTimes = keyTimes
        animation.calculationMode = .discrete
        animation.duration = duration
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        return animation
    }

    func frame(at time: TimeInterval) -> CGImage {
        frame(index: frameIndex(at: time))
    }

    func frame(index: Int) -> CGImage {
        lock.lock()
        if let frame = frames[index] {
            lock.unlock()
            return frame
        }
        lock.unlock()
        let decoded = ImageDecoding.thumbnail(source, index: index, maxPixelSize: maxPixelSize)
        lock.lock()
        defer { lock.unlock() }
        guard let decoded else { return frames[0]! }
        frames[index] = decoded
        recentlyUsed.append(index)
        // Bounded cache for large animations: keep the first frame plus the last few decoded.
        if !keepsAllFrames, recentlyUsed.count > 8 {
            let evicted = recentlyUsed.removeFirst()
            if evicted != 0 { frames[evicted] = nil }
        }
        return decoded
    }

    private static func delay(_ source: CGImageSource, index: Int) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else { return 0.1 }
        let candidates: [(CFString, CFString, CFString)] = [
            (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
            (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime),
            (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime),
            (kCGImagePropertyHEICSDictionary, kCGImagePropertyHEICSUnclampedDelayTime, kCGImagePropertyHEICSDelayTime),
        ]
        for (dictionaryKey, unclampedKey, clampedKey) in candidates {
            guard let dictionary = properties[dictionaryKey] as? [CFString: Any] else { continue }
            let value = (dictionary[unclampedKey] as? Double) ?? (dictionary[clampedKey] as? Double) ?? 0.1
            // Browsers treat near-zero delays as 100 ms.
            return value < 0.011 ? 0.1 : value
        }
        return 0.1
    }
}
