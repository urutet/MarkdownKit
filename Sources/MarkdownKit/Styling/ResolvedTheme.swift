import SwiftUI
import CoreText
#if canImport(UIKit)
import UIKit
typealias PlatformFont = UIFont
#elseif canImport(AppKit)
import AppKit
typealias PlatformFont = NSFont
#endif

/// A theme with every color and size resolved for one environment (color scheme + Dynamic Type size).
///
/// `Sendable`, so preparation can run off the main thread. Hashing uses a precomputed fingerprint.
struct ResolvedTheme: Hashable, @unchecked Sendable {
    struct Inputs: Hashable {
        var theme: MarkdownTheme
        var colorScheme: ColorScheme
        var dynamicTypeSize: DynamicTypeSize
        var textRenderer: MarkdownTextRenderer
    }

    let inputs: Inputs
    let fingerprint: Int
    let baseSize: CGFloat

    // Resolved colors.
    let textColor: Color.Resolved
    let secondaryColor: Color.Resolved
    let linkColor: Color.Resolved
    let inlineCodeColor: Color.Resolved?
    let inlineCodeBackground: Color.Resolved?
    let headingColors: [Color.Resolved?]
    let quoteTextColor: Color.Resolved?
    let tableBorder: Color.Resolved
    let tableHeaderBackground: Color.Resolved?
    let tableStripe: Color.Resolved?
    let mathColor: Color.Resolved
    let codeColors: [Color.Resolved]
    let listMarkerColor: Color.Resolved?
    let checkedColor: Color.Resolved
    let uncheckedColor: Color.Resolved
    let quoteBarColor: Color.Resolved
    let quoteBackground: Color.Resolved?
    let ruleColor: Color.Resolved
    let codeBackground: Color.Resolved
    let codeHeaderBackground: Color.Resolved
    let codeHeaderColor: Color.Resolved
    let codeBorder: Color.Resolved?
    let imagePlaceholder: Color.Resolved

    var theme: MarkdownTheme { inputs.theme }
    var textRenderer: MarkdownTextRenderer { inputs.textRenderer }

    /// Must run on the main actor: SwiftUI resolves system colors synchronously on the main thread.
    @MainActor
    init(theme: MarkdownTheme, colorScheme: ColorScheme, dynamicTypeSize: DynamicTypeSize,
         textRenderer: MarkdownTextRenderer = .coreText) {
        inputs = Inputs(theme: theme, colorScheme: colorScheme, dynamicTypeSize: dynamicTypeSize, textRenderer: textRenderer)
        var environment = EnvironmentValues()
        environment.colorScheme = colorScheme
        environment.dynamicTypeSize = dynamicTypeSize
        func r(_ color: Color) -> Color.Resolved { color.resolve(in: environment) }

        baseSize = Self.scaledSize(theme.text.baseSize, for: dynamicTypeSize)
        textColor = r(theme.text.color)
        secondaryColor = r(theme.text.secondaryColor)
        linkColor = r(theme.link.color)
        inlineCodeColor = theme.inlineCode.color.map(r)
        inlineCodeBackground = theme.inlineCode.background.map(r)
        headingColors = theme.headings.map { $0.color.map(r) }
        quoteTextColor = theme.blockquote.textColor.map(r)
        tableBorder = r(theme.table.borderColor)
        tableHeaderBackground = theme.table.headerBackground.map(r)
        tableStripe = theme.table.stripeBackground.map(r)
        mathColor = r(theme.math.color ?? theme.text.color)
        codeColors = CodeTokenKind.allCases.map { r(theme.codeBlock.theme.color(for: $0)) }
        listMarkerColor = theme.list.markerColor.map(r)
        checkedColor = r(theme.list.checkedColor)
        uncheckedColor = r(theme.list.uncheckedColor)
        quoteBarColor = r(theme.blockquote.barColor)
        quoteBackground = theme.blockquote.background.map(r)
        ruleColor = r(theme.thematicBreak.color)
        codeBackground = r(theme.codeBlock.theme.background ?? theme.codeBlock.background)
        if let codeThemeBackground = theme.codeBlock.theme.background {
            // A code theme with its own background (e.g. a dark one) gets a matching header: the
            // background shifted slightly toward the text color, and dimmed text.
            let background = r(codeThemeBackground), plain = r(theme.codeBlock.theme.plain)
            codeHeaderBackground = Self.mix(background, plain, 0.08)
            codeHeaderColor = Self.mix(background, plain, 0.6)
        } else {
            codeHeaderBackground = r(theme.codeBlock.headerBackground)
            codeHeaderColor = r(theme.codeBlock.headerColor)
        }
        codeBorder = theme.codeBlock.borderColor.map(r)
        imagePlaceholder = r(theme.image.placeholderColor)

        var hasher = Hasher()
        hasher.combine(inputs)
        fingerprint = hasher.finalize()
    }

    private static func mix(_ a: Color.Resolved, _ b: Color.Resolved, _ t: Float) -> Color.Resolved {
        Color.Resolved(red: a.red + (b.red - a.red) * t, green: a.green + (b.green - a.green) * t,
                       blue: a.blue + (b.blue - a.blue) * t, opacity: a.opacity + (b.opacity - a.opacity) * t)
    }

    static func == (lhs: ResolvedTheme, rhs: ResolvedTheme) -> Bool {
        lhs.fingerprint == rhs.fingerprint && lhs.inputs == rhs.inputs
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(fingerprint)
    }

    // MARK: Sizes

    func length(_ length: MarkdownLength, fontScale: CGFloat = 1) -> CGFloat {
        length.resolve(fontSize: baseSize * fontScale)
    }

    func size(_ font: MarkdownFont) -> CGFloat {
        (baseSize * font.scale).rounded(toPlaces: 2)
    }

    /// Body text size by Dynamic Type category (Apple's `.body` text style metrics).
    static func bodySize(for size: DynamicTypeSize) -> CGFloat {
        switch size {
        case .xSmall: 14
        case .small: 15
        case .medium: 16
        case .large: 17
        case .xLarge: 19
        case .xxLarge: 21
        case .xxxLarge: 23
        case .accessibility1: 28
        case .accessibility2: 33
        case .accessibility3: 40
        case .accessibility4: 47
        case .accessibility5: 53
        @unknown default: 17
        }
    }

    static func scaledSize(_ base: CGFloat?, for size: DynamicTypeSize) -> CGFloat {
        #if os(macOS)
        let platformDefault: CGFloat = 13
        #else
        let platformDefault: CGFloat = 17
        #endif
        let base = base ?? platformDefault
        return (base * bodySize(for: size) / 17).rounded(toPlaces: 2)
    }

    // MARK: Fonts

    func font(_ font: MarkdownFont, bold: Bool = false, italic: Bool = false, monospaced: Bool = false) -> Font {
        let weight = bold ? max(font.weight, theme.strongWeight) : font.weight
        var result = Font.system(size: size(font), weight: weight, design: monospaced ? .monospaced : font.design)
        if italic || font.italic { result = result.italic() }
        return result
    }

    func platformFont(_ font: MarkdownFont, bold: Bool = false, italic: Bool = false, monospaced: Bool = false) -> PlatformFont {
        let weight = bold ? max(font.weight, theme.strongWeight) : font.weight
        let pointSize = size(font)
        var result: PlatformFont
        if monospaced || font.design == .monospaced {
            result = .monospacedSystemFont(ofSize: pointSize, weight: weight.platformWeight)
        } else {
            result = .systemFont(ofSize: pointSize, weight: weight.platformWeight)
            if font.design != .default, let design = font.design.platformDesign,
               let descriptor = result.fontDescriptor.withDesign(design) {
                #if canImport(UIKit)
                result = PlatformFont(descriptor: descriptor, size: pointSize)
                #else
                result = PlatformFont(descriptor: descriptor, size: pointSize) ?? result
                #endif
            }
        }
        if italic || font.italic {
            #if canImport(UIKit)
            if let descriptor = result.fontDescriptor.withSymbolicTraits(result.fontDescriptor.symbolicTraits.union(.traitItalic)) {
                result = PlatformFont(descriptor: descriptor, size: pointSize)
            }
            #else
            let descriptor = result.fontDescriptor.withSymbolicTraits(result.fontDescriptor.symbolicTraits.union(.italic))
            result = PlatformFont(descriptor: descriptor, size: pointSize) ?? result
            #endif
        }
        return result
    }
}

extension Font.Weight: @retroactive Comparable {
    private var order: Int {
        switch self {
        case .ultraLight: 1
        case .thin: 2
        case .light: 3
        case .regular: 4
        case .medium: 5
        case .semibold: 6
        case .bold: 7
        case .heavy: 8
        case .black: 9
        default: 4
        }
    }

    public static func < (lhs: Font.Weight, rhs: Font.Weight) -> Bool { lhs.order < rhs.order }

    var platformWeight: PlatformFont.Weight {
        switch self {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }
}

extension Font.Design {
    #if canImport(UIKit)
    var platformDesign: UIFontDescriptor.SystemDesign? {
        switch self {
        case .serif: .serif
        case .rounded: .rounded
        case .monospaced: .monospaced
        default: nil
        }
    }
    #else
    var platformDesign: NSFontDescriptor.SystemDesign? {
        switch self {
        case .serif: .serif
        case .rounded: .rounded
        case .monospaced: .monospaced
        default: nil
        }
    }
    #endif
}

extension CGFloat {
    func rounded(toPlaces places: Int) -> CGFloat {
        let factor = pow(10, CGFloat(places))
        return (self * factor).rounded() / factor
    }
}

/// Process-wide cache of resolved themes, so views don't re-resolve colors on every body evaluation.
final class ResolvedThemeCache: @unchecked Sendable {
    static let shared = ResolvedThemeCache()
    private let lock = NSLock()
    private var storage: [ResolvedTheme.Inputs: ResolvedTheme] = [:]

    @MainActor
    func theme(_ theme: MarkdownTheme, colorScheme: ColorScheme, dynamicTypeSize: DynamicTypeSize,
               textRenderer: MarkdownTextRenderer = .coreText) -> ResolvedTheme {
        let key = ResolvedTheme.Inputs(theme: theme, colorScheme: colorScheme, dynamicTypeSize: dynamicTypeSize, textRenderer: textRenderer)
        lock.lock()
        if let cached = storage[key] { lock.unlock(); return cached }
        lock.unlock()
        let resolved = ResolvedTheme(theme: theme, colorScheme: colorScheme, dynamicTypeSize: dynamicTypeSize, textRenderer: textRenderer)
        lock.lock()
        if storage.count > 32 { storage.removeAll() }
        storage[key] = resolved
        lock.unlock()
        return resolved
    }
}
