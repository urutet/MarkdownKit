import SwiftUI

/// Builds SwiftUI-ready attributed text (plus attachment segments) from inline Markdown.
struct InlineBuilder {
    struct Style {
        var font: MarkdownFont
        var color: Color.Resolved
        var bold = false
        var italic = false
        var strikethrough = false
        var link: URL?
    }

    let theme: ResolvedTheme
    let math: (any MathRendering)?

    private var segments: [InlineSegment] = []
    private var current = AttributedString()
    private var plain = ""

    init(theme: ResolvedTheme, math: (any MathRendering)?) {
        self.theme = theme
        self.math = math
    }

    static func build(_ inlines: [MarkdownInline], style: Style, theme: ResolvedTheme,
                      math: (any MathRendering)?, lineSpacing: CGFloat) -> PreparedText {
        var builder = InlineBuilder(theme: theme, math: math)
        builder.append(inlines, style: style)
        builder.flush()
        return PreparedText(rich: nil, segments: builder.segments, plainText: builder.plain,
                            lineSpacing: lineSpacing, fontSize: theme.size(style.font))
    }

    private mutating func flush() {
        guard !current.characters.isEmpty else { return }
        segments.append(.text(current))
        current = AttributedString()
    }

    mutating func append(_ inlines: [MarkdownInline], style: Style) {
        for inline in inlines { append(inline, style: style) }
    }

    mutating func append(_ inline: MarkdownInline, style: Style) {
        switch inline {
        case .text(let string):
            appendRun(string, style: style)
        case .emphasis(let children):
            var s = style
            s.italic = true
            append(children, style: s)
        case .strong(let children):
            var s = style
            s.bold = true
            append(children, style: s)
        case .strikethrough(let children):
            var s = style
            s.strikethrough = true
            append(children, style: s)
        case .code(let code):
            appendCode(code, style: style)
        case .link(let destination, let children):
            var s = style
            s.link = destination.flatMap(Self.url(from:))
            append(children, style: s)
        case .image(let source, let alt, _):
            flush()
            let height = theme.theme.emojiSize.resolve(fontSize: theme.size(style.font))
            segments.append(.image(InlineImage(url: source.flatMap(Self.url(from:)), alt: alt, height: height,
                                               fallback: run(alt.isEmpty ? "🖼" : alt, style: style))))
            plain += alt
        case .softBreak:
            appendRun(" ", style: style)
        case .lineBreak:
            appendRun("\n", style: style)
        case .math(let latex):
            appendMath(latex, style: style)
        case .emoji(let name):
            flush()
            let size = theme.theme.emojiSize.resolve(fontSize: theme.size(style.font))
            segments.append(.emoji(InlineEmoji(name: name, size: size, fallback: run(":\(name):", style: style))))
            plain += ":\(name):"
        case .html(let raw):
            appendRun(raw, style: style)
        }
    }

    private mutating func appendRun(_ string: String, style: Style) {
        current.append(run(string, style: style))
        plain += string
    }

    func run(_ string: String, style: Style) -> AttributedString {
        var run = AttributedString(string)
        run.font = theme.font(style.font, bold: style.bold, italic: style.italic)
        if let link = style.link {
            run.link = link
            run.foregroundColor = Color(theme.linkColor)
            if theme.theme.link.underline { run.underlineStyle = .single }
        } else {
            run.foregroundColor = Color(style.color)
        }
        if style.strikethrough { run.strikethroughStyle = .single }
        return run
    }

    private mutating func appendCode(_ code: String, style: Style) {
        let codeStyle = theme.theme.inlineCode
        var font = codeStyle.font
        font.scale *= style.font.scale
        // Non-breaking spaces around the code keep the background padded.
        var run = AttributedString(code.replacingOccurrences(of: "\n", with: " "))
        run.font = theme.font(font, bold: style.bold, italic: style.italic, monospaced: true)
        run.foregroundColor = Color(style.link != nil ? theme.linkColor : (theme.inlineCodeColor ?? style.color))
        if let background = theme.inlineCodeBackground { run.backgroundColor = Color(background) }
        if let link = style.link { run.link = link }
        if style.strikethrough { run.strikethroughStyle = .single }
        current.append(run)
        plain += code
    }

    private mutating func appendMath(_ latex: String, style: Style) {
        let fontSize = theme.size(style.font) * theme.theme.math.scale
        var fallbackStyle = style
        fallbackStyle.italic = true
        let fallback = run(latex, style: fallbackStyle)
        guard let math else {
            current.append(fallback)
            plain += latex
            return
        }
        flush()
        let rendered = math.render(latex: latex, display: false, fontSize: fontSize,
                                   color: theme.mathColor, font: theme.theme.math.font)
        segments.append(.math(PreparedMath(latex: latex, isDisplay: false, image: rendered?.image,
                                           descent: rendered?.descent ?? 0, fallback: fallback)))
        plain += latex
    }

    static func url(from destination: String) -> URL? {
        if let url = URL(string: destination) { return url }
        return destination.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed).flatMap(URL.init(string:))
    }
}
