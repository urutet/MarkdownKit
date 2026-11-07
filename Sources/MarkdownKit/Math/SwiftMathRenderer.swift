import SwiftUI
import SwiftMath
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Renders TeX with SwiftMath (CoreText-based, no web view) into cached bitmaps.
///
/// Formulas are typeset at 3× the font size and shown at scale 3, so they stay sharp on every display
/// without depending on the (thread-unsafe) screen scale.
final class SwiftMathRenderer: MathRendering, @unchecked Sendable {
    static let shared = SwiftMathRenderer()

    private struct Key: Hashable, Sendable {
        var latex: String
        var display: Bool
        var fontSize: CGFloat
        var color: Color.Resolved
        var font: MathFontName
    }

    private enum Entry: Sendable {
        case rendered(RenderedMath)
        case failed
    }

    private let cache = SendableCache<Key, Entry>(totalCostLimit: 32 << 20)
    /// SwiftMath keeps shared mutable font tables; serialize typesetting.
    private let lock = NSLock()
    static let oversampling: CGFloat = 3

    func render(latex: String, display: Bool, fontSize: CGFloat, color: Color.Resolved, font: MathFontName) -> RenderedMath? {
        let key = Key(latex: latex, display: display, fontSize: fontSize, color: color, font: font)
        if let entry = cache[key] {
            if case .rendered(let math) = entry { return math }
            return nil
        }
        let result = autoreleasepool { typeset(key) }
        switch result {
        case let math?:
            cache.set(.rendered(math), for: key, cost: math.image.cgImage.bytesPerRow * math.image.cgImage.height)
        case nil:
            cache.set(.failed, for: key, cost: 64)
        }
        return result
    }

    private func typeset(_ key: Key) -> RenderedMath? {
        let scale = Self.oversampling
        #if canImport(UIKit)
        let textColor = UIColor(cgColor: key.color.cgColor)
        #else
        let textColor = NSColor(cgColor: key.color.cgColor) ?? .textColor
        #endif
        var math = MathImage(latex: key.latex, fontSize: key.fontSize * scale, textColor: textColor,
                             labelMode: key.display ? .display : .text, textAlignment: .left)
        math.font = key.font.swiftMathFont
        lock.lock()
        let (error, image, info) = math.asImage()
        lock.unlock()
        guard error == nil, let image, let info else { return nil }
        #if canImport(UIKit)
        guard let cgImage = image.cgImage else { return nil }
        let imageScale = image.scale * scale
        #else
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        let imageScale = CGFloat(cgImage.width) / image.size.width * scale
        #endif
        let sendable = SendableImage(cgImage: cgImage, scale: imageScale)
        // MathImage centers the formula vertically; derive the baseline offset from its layout.
        let height = sendable.size.height
        let ascent = info.ascent / scale
        let descent = info.descent / scale
        let padding = max(0, (height - ascent - descent) / 2)
        return RenderedMath(image: sendable, descent: descent + padding)
    }
}

extension MathFontName {
    var swiftMathFont: MathFont {
        switch self {
        case .latinModern: .latinModernFont
        case .termes: .termesFont
        case .xits: .xitsFont
        case .asana: .asanaFont
        case .euler: .eulerFont
        case .fira: .firaFont
        case .notoSans: .notoSansFont
        case .libertinus: .libertinusFont
        case .garamond: .garamondFont
        case .kpMathLight: .kpMathLightFont
        case .kpMathSans: .kpMathSansFont
        case .leteSans: .leteSansFont
        }
    }
}
