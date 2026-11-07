import SwiftUI

/// Font description relative to the theme's base font size.
public struct MarkdownFont: Hashable, Sendable {
    /// Multiplier applied to the base font size.
    public var scale: CGFloat
    public var weight: Font.Weight
    public var design: Font.Design
    public var italic: Bool

    public init(scale: CGFloat = 1, weight: Font.Weight = .regular, design: Font.Design = .default, italic: Bool = false) {
        self.scale = scale
        self.weight = weight
        self.design = design
        self.italic = italic
    }

    public static let body = MarkdownFont()
    public static let monospaced = MarkdownFont(scale: 0.9, design: .monospaced)
}

/// Complete visual description of rendered Markdown.
///
/// All lengths are ``MarkdownLength`` values; `em` lengths are relative to the base font size, which
/// follows Dynamic Type unless ``Text-swift.struct/baseSize`` is fixed.
public struct MarkdownTheme: Hashable, Sendable {
    public struct Text: Hashable, Sendable {
        /// Base font size in points at the default (`.large`) Dynamic Type size.
        /// `nil` uses the platform body text size. Always scaled with Dynamic Type.
        public var baseSize: CGFloat?
        public var font: MarkdownFont
        public var color: Color
        public var secondaryColor: Color
        public var lineSpacing: MarkdownLength

        public init(baseSize: CGFloat? = nil, font: MarkdownFont = .body, color: Color = .primary,
                    secondaryColor: Color = .secondary, lineSpacing: MarkdownLength = .em(0.2)) {
            self.baseSize = baseSize
            self.font = font
            self.color = color
            self.secondaryColor = secondaryColor
            self.lineSpacing = lineSpacing
        }
    }

    public struct Link: Hashable, Sendable {
        public var color: Color
        public var underline: Bool
        public init(color: Color = .accentColor, underline: Bool = false) {
            self.color = color
            self.underline = underline
        }
    }

    public struct Heading: Hashable, Sendable {
        public var font: MarkdownFont
        public var color: Color?
        public var spacingBefore: MarkdownLength
        public var spacingAfter: MarkdownLength
        /// Draws a divider below the heading.
        public var divider: Bool

        public init(font: MarkdownFont, color: Color? = nil, spacingBefore: MarkdownLength = .em(0.6),
                    spacingAfter: MarkdownLength = .em(0.1), divider: Bool = false) {
            self.font = font
            self.color = color
            self.spacingBefore = spacingBefore
            self.spacingAfter = spacingAfter
            self.divider = divider
        }
    }

    public struct InlineCode: Hashable, Sendable {
        public var font: MarkdownFont
        public var color: Color?
        public var background: Color?
        public init(font: MarkdownFont = .monospaced, color: Color? = nil,
                    background: Color? = Color.gray.opacity(0.15)) {
            self.font = font
            self.color = color
            self.background = background
        }
    }

    public struct CodeBlock: Hashable, Sendable {
        public var font: MarkdownFont
        public var background: Color
        public var headerBackground: Color
        public var headerColor: Color
        public var borderColor: Color?
        public var cornerRadius: MarkdownLength
        public var padding: MarkdownLength
        public var showsHeader: Bool
        public var showsCopyButton: Bool
        /// Wrap long lines instead of scrolling horizontally.
        public var wrapsLines: Bool
        public var theme: CodeTheme

        public init(font: MarkdownFont = MarkdownFont(scale: 0.85, design: .monospaced),
                    background: Color = .dynamic(light: Color(hex: 0xF6F7F9), dark: Color(hex: 0x1E1F22)),
                    headerBackground: Color = .dynamic(light: Color(hex: 0xECEEF1), dark: Color(hex: 0x2A2B2F)),
                    headerColor: Color = .secondary,
                    borderColor: Color? = nil,
                    cornerRadius: MarkdownLength = .em(0.6),
                    padding: MarkdownLength = .em(0.85),
                    showsHeader: Bool = true,
                    showsCopyButton: Bool = true,
                    wrapsLines: Bool = false,
                    theme: CodeTheme = .xcode) {
            self.font = font
            self.background = background
            self.headerBackground = headerBackground
            self.headerColor = headerColor
            self.borderColor = borderColor
            self.cornerRadius = cornerRadius
            self.padding = padding
            self.showsHeader = showsHeader
            self.showsCopyButton = showsCopyButton
            self.wrapsLines = wrapsLines
            self.theme = theme
        }
    }

    public struct Blockquote: Hashable, Sendable {
        public var barColor: Color
        public var barWidth: MarkdownLength
        public var indent: MarkdownLength
        public var textColor: Color?
        public var background: Color?

        public init(barColor: Color = Color.gray.opacity(0.4), barWidth: MarkdownLength = .em(0.2),
                    indent: MarkdownLength = .em(0.9), textColor: Color? = .secondary, background: Color? = nil) {
            self.barColor = barColor
            self.barWidth = barWidth
            self.indent = indent
            self.textColor = textColor
            self.background = background
        }
    }

    public struct List: Hashable, Sendable {
        /// Width reserved for bullets and numbers.
        public var markerWidth: MarkdownLength
        public var markerSpacing: MarkdownLength
        public var itemSpacing: MarkdownLength
        /// Bullets by nesting level (cycled).
        public var bullets: [String]
        public var markerColor: Color?
        public var checkedColor: Color
        public var uncheckedColor: Color

        public init(markerWidth: MarkdownLength = .em(1.2), markerSpacing: MarkdownLength = .em(0.4),
                    itemSpacing: MarkdownLength = .em(0.3), bullets: [String] = ["•", "◦", "▪︎"],
                    markerColor: Color? = .secondary, checkedColor: Color = .accentColor,
                    uncheckedColor: Color = .secondary) {
            self.markerWidth = markerWidth
            self.markerSpacing = markerSpacing
            self.itemSpacing = itemSpacing
            self.bullets = bullets
            self.markerColor = markerColor
            self.checkedColor = checkedColor
            self.uncheckedColor = uncheckedColor
        }
    }

    public struct Table: Hashable, Sendable {
        public var font: MarkdownFont
        public var headerFont: MarkdownFont
        public var headerBackground: Color?
        /// Background of every other body row. `nil` disables striping.
        public var stripeBackground: Color?
        public var borderColor: Color
        public var borderWidth: CGFloat
        public var cornerRadius: MarkdownLength
        public var horizontalPadding: MarkdownLength
        public var verticalPadding: MarkdownLength
        /// Columns wider than this wrap their text.
        public var maxColumnWidth: MarkdownLength
        public var minColumnWidth: MarkdownLength

        public init(font: MarkdownFont = MarkdownFont(scale: 0.9),
                    headerFont: MarkdownFont = MarkdownFont(scale: 0.9, weight: .semibold),
                    headerBackground: Color? = Color.gray.opacity(0.12),
                    stripeBackground: Color? = Color.gray.opacity(0.05),
                    borderColor: Color = Color.gray.opacity(0.3),
                    borderWidth: CGFloat = 1,
                    cornerRadius: MarkdownLength = .em(0.5),
                    horizontalPadding: MarkdownLength = .em(0.65),
                    verticalPadding: MarkdownLength = .em(0.45),
                    maxColumnWidth: MarkdownLength = .em(16),
                    minColumnWidth: MarkdownLength = .em(2.5)) {
            self.font = font
            self.headerFont = headerFont
            self.headerBackground = headerBackground
            self.stripeBackground = stripeBackground
            self.borderColor = borderColor
            self.borderWidth = borderWidth
            self.cornerRadius = cornerRadius
            self.horizontalPadding = horizontalPadding
            self.verticalPadding = verticalPadding
            self.maxColumnWidth = maxColumnWidth
            self.minColumnWidth = minColumnWidth
        }

        public static let `default` = Table()
        public static let plain = Table(headerBackground: nil, stripeBackground: nil)
        public static let striped = Table()
    }

    public struct ThematicBreak: Hashable, Sendable {
        public var color: Color
        public var thickness: CGFloat
        public var spacing: MarkdownLength
        public init(color: Color = Color.gray.opacity(0.3), thickness: CGFloat = 1, spacing: MarkdownLength = .em(0.5)) {
            self.color = color
            self.thickness = thickness
            self.spacing = spacing
        }
    }

    public struct Image: Hashable, Sendable {
        public var maxHeight: MarkdownLength
        public var cornerRadius: MarkdownLength
        /// Height reserved for a block image whose size is still unknown.
        public var placeholderHeight: MarkdownLength
        public var placeholderColor: Color
        public init(maxHeight: MarkdownLength = .em(22), cornerRadius: MarkdownLength = .em(0.5),
                    placeholderHeight: MarkdownLength = .em(10), placeholderColor: Color = Color.gray.opacity(0.12)) {
            self.maxHeight = maxHeight
            self.cornerRadius = cornerRadius
            self.placeholderHeight = placeholderHeight
            self.placeholderColor = placeholderColor
        }
    }

    public struct Math: Hashable, Sendable {
        public var scale: CGFloat
        public var color: Color?
        public var font: MathFontName
        public init(scale: CGFloat = 1.05, color: Color? = nil, font: MathFontName = .latinModern) {
            self.scale = scale
            self.color = color
            self.font = font
        }
    }

    public var text: Text
    /// Vertical space between blocks.
    public var blockSpacing: MarkdownLength
    public var strongWeight: Font.Weight
    public var link: Link
    /// Heading styles for levels 1 through 6.
    public var headings: [Heading]
    public var inlineCode: InlineCode
    public var codeBlock: CodeBlock
    public var blockquote: Blockquote
    public var list: List
    public var table: Table
    public var thematicBreak: ThematicBreak
    public var image: Image
    public var math: Math
    /// Size of inline custom emoji and inline images without explicit size, relative to the line's font.
    public var emojiSize: MarkdownLength

    public init(text: Text = Text(),
                blockSpacing: MarkdownLength = .em(0.75),
                strongWeight: Font.Weight = .semibold,
                link: Link = Link(),
                headings: [Heading] = MarkdownTheme.defaultHeadings,
                inlineCode: InlineCode = InlineCode(),
                codeBlock: CodeBlock = CodeBlock(),
                blockquote: Blockquote = Blockquote(),
                list: List = List(),
                table: Table = Table(),
                thematicBreak: ThematicBreak = ThematicBreak(),
                image: Image = Image(),
                math: Math = Math(),
                emojiSize: MarkdownLength = .em(1.25)) {
        self.text = text
        self.blockSpacing = blockSpacing
        self.strongWeight = strongWeight
        self.link = link
        self.headings = headings
        self.inlineCode = inlineCode
        self.codeBlock = codeBlock
        self.blockquote = blockquote
        self.list = list
        self.table = table
        self.thematicBreak = thematicBreak
        self.image = image
        self.math = math
        self.emojiSize = emojiSize
    }

    public static let defaultHeadings: [Heading] = [
        Heading(font: MarkdownFont(scale: 1.6, weight: .bold), spacingBefore: .em(0.8)),
        Heading(font: MarkdownFont(scale: 1.35, weight: .bold), spacingBefore: .em(0.7)),
        Heading(font: MarkdownFont(scale: 1.18, weight: .semibold)),
        Heading(font: MarkdownFont(scale: 1.05, weight: .semibold)),
        Heading(font: MarkdownFont(scale: 1.0, weight: .semibold)),
        Heading(font: MarkdownFont(scale: 0.9, weight: .semibold), color: .secondary),
    ]

    /// The default theme: system fonts, adaptive colors.
    public static let `default` = MarkdownTheme()

    /// A denser theme suited to chat bubbles.
    public static let compact = MarkdownTheme(
        text: Text(lineSpacing: .em(0.12)),
        blockSpacing: .em(0.55),
        headings: defaultHeadings.map { var h = $0; h.font.scale = max(1, h.font.scale * 0.85); h.spacingBefore = .em(0.4); return h }
    )

    /// Heading style for a level in `1...6`.
    public func heading(_ level: Int) -> Heading {
        headings[min(max(level, 1), headings.count) - 1]
    }
}

/// Math fonts bundled with SwiftMath.
public enum MathFontName: String, Hashable, Sendable, CaseIterable {
    case latinModern, termes, xits, asana, euler, fira, notoSans, libertinus, garamond, kpMathLight, kpMathSans, leteSans
}
