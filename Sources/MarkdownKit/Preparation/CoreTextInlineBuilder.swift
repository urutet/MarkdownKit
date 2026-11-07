import SwiftUI
import CoreText

/// Custom attributes understood by the table renderer (CoreText doesn't draw these itself).
enum CoreTextKeys {
    static let link = NSAttributedString.Key("MarkdownKit.link")
    static let background = NSAttributedString.Key("MarkdownKit.background")
    static let strikethrough = NSAttributedString.Key("MarkdownKit.strikethrough")
    static let attachment = NSAttributedString.Key("MarkdownKit.attachment")
    static let foreground = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
    static let font = NSAttributedString.Key(kCTFontAttributeName as String)
    static let runDelegate = NSAttributedString.Key(kCTRunDelegateAttributeName as String)
}

/// Inline image drawn inside CoreText-laid-out text (math in table cells).
final class CoreTextAttachment: @unchecked Sendable {
    let image: SendableImage
    let ascent: CGFloat
    let descent: CGFloat
    let width: CGFloat

    init(image: SendableImage, descent: CGFloat) {
        self.image = image
        let size = image.size
        self.descent = descent
        self.ascent = size.height - descent
        self.width = size.width
    }

    func makeRunDelegate() -> CTRunDelegate? {
        var callbacks = CTRunDelegateCallbacks(
            version: kCTRunDelegateVersion1,
            dealloc: { pointer in Unmanaged<CoreTextAttachment>.fromOpaque(pointer).release() },
            getAscent: { Unmanaged<CoreTextAttachment>.fromOpaque($0).takeUnretainedValue().ascent },
            getDescent: { Unmanaged<CoreTextAttachment>.fromOpaque($0).takeUnretainedValue().descent },
            getWidth: { Unmanaged<CoreTextAttachment>.fromOpaque($0).takeUnretainedValue().width }
        )
        return CTRunDelegateCreate(&callbacks, Unmanaged.passRetained(self).toOpaque())
    }
}

/// Builds CoreText attributed strings from inline Markdown (used for table cells).
struct CoreTextInlineBuilder {
    struct Style {
        var font: MarkdownFont
        var color: CGColor
        var bold = false
        var italic = false
        var strikethrough = false
        var link: URL?
        var code = false
    }

    private struct FontKey: Hashable {
        var bold: Bool
        var italic: Bool
        var code: Bool
        var scale: CGFloat
        var weight: Font.Weight
    }

    let theme: ResolvedTheme
    let math: (any MathRendering)?
    let linkColor: CGColor
    let codeColor: CGColor?
    let codeBackground: CGColor?
    private var fonts: [FontKey: PlatformFont] = [:]
    private(set) var output = NSMutableAttributedString()

    init(theme: ResolvedTheme, math: (any MathRendering)?) {
        self.theme = theme
        self.math = math
        linkColor = theme.linkColor.cgColor
        codeColor = theme.inlineCodeColor?.cgColor
        codeBackground = theme.inlineCodeBackground?.cgColor
    }

    mutating func build(_ inlines: [MarkdownInline], style: Style) -> NSAttributedString {
        output = NSMutableAttributedString()
        append(inlines, style: style)
        return output
    }

    private mutating func font(for style: Style) -> PlatformFont {
        let key = FontKey(bold: style.bold, italic: style.italic, code: style.code, scale: style.font.scale, weight: style.font.weight)
        if let font = fonts[key] { return font }
        var markdownFont = style.font
        if style.code { markdownFont.scale *= theme.theme.inlineCode.font.scale }
        let font = theme.platformFont(markdownFont, bold: style.bold, italic: style.italic, monospaced: style.code)
        fonts[key] = font
        return font
    }

    private mutating func append(_ inlines: [MarkdownInline], style: Style) {
        for inline in inlines { append(inline, style: style) }
    }

    private mutating func append(_ inline: MarkdownInline, style: Style) {
        switch inline {
        case .text(let string), .html(let string):
            appendRun(string, style: style)
        case .emphasis(let children):
            var s = style; s.italic = true; append(children, style: s)
        case .strong(let children):
            var s = style; s.bold = true; append(children, style: s)
        case .strikethrough(let children):
            var s = style; s.strikethrough = true; append(children, style: s)
        case .code(let code):
            var s = style; s.code = true; appendRun(code, style: s)
        case .link(let destination, let children):
            var s = style; s.link = destination.flatMap(InlineBuilder.url(from:)); append(children, style: s)
        case .image(_, let alt, _):
            appendRun(alt.isEmpty ? "🖼" : alt, style: style)
        case .softBreak:
            appendRun(" ", style: style)
        case .lineBreak:
            appendRun("\u{2028}", style: style)
        case .math(let latex):
            appendMath(latex, style: style)
        case .emoji(let name):
            appendRun(":\(name):", style: style)
        }
    }

    private mutating func attributes(for style: Style) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            CoreTextKeys.font: font(for: style),
            CoreTextKeys.foreground: style.link != nil ? linkColor : (style.code ? (codeColor ?? style.color) : style.color),
        ]
        if let link = style.link { attributes[CoreTextKeys.link] = link }
        if style.strikethrough { attributes[CoreTextKeys.strikethrough] = true }
        if style.code, let codeBackground { attributes[CoreTextKeys.background] = codeBackground }
        return attributes
    }

    private mutating func appendRun(_ string: String, style: Style) {
        guard !string.isEmpty else { return }
        output.append(NSAttributedString(string: string, attributes: attributes(for: style)))
    }

    private mutating func appendMath(_ latex: String, style: Style) {
        let fontSize = theme.size(style.font) * theme.theme.math.scale
        guard let rendered = math?.render(latex: latex, display: false, fontSize: fontSize,
                                          color: theme.mathColor, font: theme.theme.math.font) else {
            var s = style; s.italic = true
            appendRun(latex, style: s)
            return
        }
        let attachment = CoreTextAttachment(image: rendered.image, descent: rendered.descent)
        var attributes = attributes(for: style)
        attributes[CoreTextKeys.attachment] = attachment
        if let delegate = attachment.makeRunDelegate() { attributes[CoreTextKeys.runDelegate] = delegate }
        output.append(NSAttributedString(string: "\u{FFFC}", attributes: attributes))
    }
}
