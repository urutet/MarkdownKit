import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import MarkdownKit

enum TestImages {
    static func solid(_ gray: CGFloat, size: Int = 40) -> CGImage {
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: gray, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return context.makeImage()!
    }

    /// Encodes an animated image (GIF or APNG) with the given per-frame delays.
    static func animated(type: UTType, delays: [Double]) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, delays.count, nil)!
        for (index, delay) in delays.enumerated() {
            let properties: [CFString: Any] = type == .gif
                ? [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]]
                : [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGDelayTime: delay]]
            CGImageDestinationAddImage(destination, solid(CGFloat(index) / CGFloat(delays.count)), properties as CFDictionary)
        }
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    static func png() -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, solid(0.5, size: 64), nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }
}

@Suite struct ImageTests {
    @Test func decodesStillImageWithDownsampling() throws {
        let image = try #require(MarkdownImage(data: TestImages.png(), maxPixelSize: 32))
        #expect(!image.isAnimated)
        #expect(image.pixelSize == CGSize(width: 32, height: 32))
    }

    @Test(arguments: [UTType.gif, UTType.png])
    func decodesAnimationTiming(type: UTType) throws {
        let image = try #require(MarkdownImage(data: TestImages.animated(type: type, delays: [0.1, 0.2, 0.3])))
        guard case .animated(let animation) = image.content else { Issue.record("not animated"); return }
        #expect(animation.frameCount == 3)
        #expect(abs(animation.duration - 0.6) < 0.01)
        #expect(animation.frameIndex(at: 0.05) == 0)
        #expect(animation.frameIndex(at: 0.15) == 1)
        #expect(animation.frameIndex(at: 0.45) == 2)
        #expect(animation.frameIndex(at: 0.65) == 0) // loops
    }

    @Test func zeroDelaysAreClamped() throws {
        let image = try #require(MarkdownImage(data: TestImages.animated(type: .gif, delays: [0, 0])))
        guard case .animated(let animation) = image.content else { Issue.record("not animated"); return }
        #expect(animation.delays.allSatisfy { $0 >= 0.1 - 0.0001 })
    }

    @Test func loaderLoadsFileURLsAndCaches() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mk-\(UUID().uuidString).gif")
        try TestImages.animated(type: .gif, delays: [0.1, 0.1]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let loader = DefaultMarkdownImageLoader()
        #expect(loader.cachedImage(for: url, maxPixelSize: 100) == nil)
        async let first = loader.loadImage(from: url, maxPixelSize: 100)
        async let second = loader.loadImage(from: url, maxPixelSize: 100)
        let (a, b) = try await (first, second)
        #expect(a.isAnimated && b.isAnimated)
        #expect(loader.cachedImage(for: url, maxPixelSize: 90) != nil)
        #expect(loader.knownPixelSize(for: url) == CGSize(width: 40, height: 40))
    }

    @Test func commonShortcodes() {
        #expect(MarkdownEmojiShortcodes.common["rocket"] == "🚀")
    }

    @MainActor @Test func preparesInlineAttachmentSegments() throws {
        let theme = ResolvedTheme(theme: .default, colorScheme: .light, dynamicTypeSize: .large)
        var options = MarkdownParseOptions()
        options.hasEmojiProvider = true
        let document = MarkdownPipeline.prepare(MarkdownRequest(text: "Hi :rocket: and ![badge](https://x.y/b.png) end",
                                                                theme: theme, options: options, isStreaming: false))
        guard case .text(let text, _) = try #require(document.blocks.first?.content) else { Issue.record("no text"); return }
        #expect(text.hasAttachments)
        #expect(text.emojiNames == ["rocket"])
        #expect(text.imageURLs == [URL(string: "https://x.y/b.png")!])
    }
}
