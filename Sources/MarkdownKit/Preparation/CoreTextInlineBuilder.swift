import SwiftUI
import CoreText

/// Custom attributes understood by the CoreText renderers (CoreText doesn't draw these itself).
enum CoreTextKeys {
    static let link = NSAttributedString.Key("MarkdownKit.link")
    static let background = NSAttributedString.Key("MarkdownKit.background")
    static let strikethrough = NSAttributedString.Key("MarkdownKit.strikethrough")
    static let attachment = NSAttributedString.Key("MarkdownKit.attachment")
    static let foreground = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
    static let font = NSAttributedString.Key(kCTFontAttributeName as String)
    static let runDelegate = NSAttributedString.Key(kCTRunDelegateAttributeName as String)
    static let underline = NSAttributedString.Key(kCTUnderlineStyleAttributeName as String)
}

/// An inline object laid out by CoreText through a run delegate.
final class CoreTextAttachment: @unchecked Sendable {
    enum Content: Sendable {
        /// Rendered at preparation time (math).
        case image(SendableImage, accessibilityLabel: String)
        /// Resolved at display time (custom emoji, remote images).
        case emoji(name: String, fallback: String)
        case remoteImage(URL, alt: String)
    }

    let id: Int
    let content: Content
    let ascent: CGFloat
    let descent: CGFloat
    private let lock = NSLock()
    private var _width: CGFloat

    var width: CGFloat {
        lock.lock(); defer { lock.unlock() }
        return _width
    }

    init(id: Int, content: Content, ascent: CGFloat, descent: CGFloat, width: CGFloat) {
        self.id = id
        self.content = content
        self.ascent = ascent
        self.descent = descent
        _width = width
    }

    convenience init(id: Int, image: SendableImage, descent: CGFloat, label: String) {
        let size = image.size
        self.init(id: id, content: .image(image, accessibilityLabel: label), ascent: size.height - descent,
                  descent: descent, width: size.width)
    }

    /// Updates the width (e.g. once an image's aspect ratio is known). Returns `true` if it changed.
    func setWidth(_ width: CGFloat) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard abs(_width - width) > 0.5 else { return false }
        _width = width
        return true
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

/// Builds CoreText attributed strings from inline Markdown (text blocks and table cells).
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
        var design: Font.Design
    }

    let theme: ResolvedTheme
    let math: (any MathRendering)?
    /// Emit attachments for custom emoji and inline images (text blocks). Table cells use text fallbacks.
    var placeholderAttachments = false
    let linkColor: CGColor
    let codeColor: CGColor?
    let codeBackground: CGColor?
    private var fonts: [FontKey: PlatformFont] = [:]
    private(set) var output = NSMutableAttributedString()
    private(set) var attachments: [CoreTextAttachment] = []
    private(set) var plain = ""

    init(theme: ResolvedTheme, math: (any MathRendering)?, placeholderAttachments: Bool = false) {
        self.theme = theme
        self.math = math
        self.placeholderAttachments = placeholderAttachments
        linkColor = theme.linkColor.cgColor
        codeColor = theme.inlineCodeColor?.cgColor
        codeBackground = theme.inlineCodeBackground?.cgColor
    }

    mutating func build(_ inlines: [MarkdownInline], style: Style) -> NSAttributedString {
        output = NSMutableAttributedString()
        attachments = []
        plain = ""
        append(inlines, style: style)
        return output
    }

    mutating func font(for style: Style) -> PlatformFont {
        let key = FontKey(bold: style.bold, italic: style.italic, code: style.code, scale: style.font.scale,
                          weight: style.font.weight, design: style.font.design)
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
            var s = style; s.code = true
            appendRun(code.replacingOccurrences(of: "\n", with: " "), style: s)
        case .link(let destination, let children):
            var s = style; s.link = destination.flatMap(InlineBuilder.url(from:)); append(children, style: s)
        case .image(let source, let alt, _):
            if placeholderAttachments, let url = source.flatMap(InlineBuilder.url(from:)) {
                let size = theme.theme.emojiSize.resolve(fontSize: theme.size(style.font))
                appendAttachment(.remoteImage(url, alt: alt), size: size, style: style, plainText: alt)
            } else {
                appendRun(alt.isEmpty ? "🖼" : alt, style: style)
            }
        case .softBreak:
            appendRun(" ", style: style)
        case .lineBreak:
            appendRun("\u{2028}", style: style)
        case .math(let latex):
            appendMath(latex, style: style)
        case .emoji(let name):
            let common = MarkdownEmojiShortcodes.common[name]
            if placeholderAttachments {
                let size = theme.theme.emojiSize.resolve(fontSize: theme.size(style.font))
                appendAttachment(.emoji(name: name, fallback: common ?? ":\(name):"), size: size, style: style,
                                 plainText: common ?? ":\(name):")
            } else {
                appendRun(common ?? ":\(name):", style: style)
            }
        }
    }

    private mutating func attributes(for style: Style) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            CoreTextKeys.font: font(for: style),
            CoreTextKeys.foreground: style.link != nil ? linkColor : (style.code ? (codeColor ?? style.color) : style.color),
        ]
        if let link = style.link {
            attributes[CoreTextKeys.link] = link
            if theme.theme.link.underline { attributes[CoreTextKeys.underline] = CTUnderlineStyle.single.rawValue }
        }
        if style.strikethrough { attributes[CoreTextKeys.strikethrough] = true }
        if style.code, let codeBackground { attributes[CoreTextKeys.background] = codeBackground }
        return attributes
    }

    private mutating func appendRun(_ string: String, style: Style) {
        guard !string.isEmpty else { return }
        output.append(NSAttributedString(string: string, attributes: attributes(for: style)))
        plain += string
    }

    private mutating func appendAttachment(_ content: CoreTextAttachment.Content, size: CGFloat, style: Style, plainText: String) {
        let attachment = CoreTextAttachment(id: attachments.count, content: content, ascent: size * 0.8,
                                            descent: size * 0.2, width: size)
        insert(attachment, style: style)
        plain += plainText
    }

    private mutating func insert(_ attachment: CoreTextAttachment, style: Style) {
        var attributes = attributes(for: style)
        attributes[CoreTextKeys.attachment] = attachment
        if let delegate = attachment.makeRunDelegate() { attributes[CoreTextKeys.runDelegate] = delegate }
        output.append(NSAttributedString(string: "\u{FFFC}", attributes: attributes))
        attachments.append(attachment)
    }

    private mutating func appendMath(_ latex: String, style: Style) {
        let fontSize = theme.size(style.font) * theme.theme.math.scale
        guard let rendered = math?.render(latex: latex, display: false, fontSize: fontSize,
                                          color: theme.mathColor, font: theme.theme.math.font) else {
            var s = style; s.italic = true
            appendRun(latex, style: s)
            return
        }
        insert(CoreTextAttachment(id: attachments.count, image: rendered.image, descent: rendered.descent, label: latex), style: style)
        plain += latex
    }
}
