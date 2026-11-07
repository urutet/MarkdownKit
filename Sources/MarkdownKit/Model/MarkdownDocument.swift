import Foundation

/// A parsed Markdown document: an immutable, `Sendable` tree of blocks.
///
/// Produced off the main thread by the parser and consumed by the preparer.
public struct MarkdownDocument: Hashable, Sendable {
    public var blocks: [MarkdownBlock]

    public init(blocks: [MarkdownBlock]) {
        self.blocks = blocks
    }
}

/// Block-level Markdown element.
public indirect enum MarkdownBlock: Hashable, Sendable {
    case paragraph([MarkdownInline])
    case heading(level: Int, [MarkdownInline])
    case blockquote([MarkdownBlock])
    case list(MarkdownList)
    case codeBlock(MarkdownCodeBlock)
    case table(MarkdownTable)
    case thematicBreak
    case mathBlock(String)
    case htmlBlock(String)
}

public struct MarkdownList: Hashable, Sendable {
    public var isOrdered: Bool
    public var startIndex: Int
    public var isTight: Bool
    public var items: [MarkdownListItem]

    public init(isOrdered: Bool, startIndex: Int = 1, isTight: Bool = true, items: [MarkdownListItem]) {
        self.isOrdered = isOrdered
        self.startIndex = startIndex
        self.isTight = isTight
        self.items = items
    }
}

public struct MarkdownListItem: Hashable, Sendable {
    /// `nil` for a regular item, `true`/`false` for a GFM task list item.
    public var checkbox: Bool?
    public var blocks: [MarkdownBlock]

    public init(checkbox: Bool? = nil, blocks: [MarkdownBlock]) {
        self.checkbox = checkbox
        self.blocks = blocks
    }
}

public struct MarkdownCodeBlock: Hashable, Sendable {
    public var language: String?
    public var code: String
    /// `false` while streaming an unterminated fence.
    public var isClosed: Bool

    public init(language: String?, code: String, isClosed: Bool = true) {
        self.language = language
        self.code = code
        self.isClosed = isClosed
    }
}

public struct MarkdownTable: Hashable, Sendable {
    public enum Alignment: Hashable, Sendable {
        case none, left, center, right
    }

    public var alignments: [Alignment]
    public var header: [[MarkdownInline]]
    public var rows: [[[MarkdownInline]]]

    public init(alignments: [Alignment], header: [[MarkdownInline]], rows: [[[MarkdownInline]]]) {
        self.alignments = alignments
        self.header = header
        self.rows = rows
    }

    public var columnCount: Int {
        max(header.count, rows.reduce(0) { max($0, $1.count) }, alignments.count)
    }
}

/// Inline-level Markdown element.
public indirect enum MarkdownInline: Hashable, Sendable {
    case text(String)
    case emphasis([MarkdownInline])
    case strong([MarkdownInline])
    case strikethrough([MarkdownInline])
    case code(String)
    case link(destination: String?, [MarkdownInline])
    case image(source: String?, alt: String, title: String?)
    case softBreak
    case lineBreak
    case math(String)
    case emoji(String)
    case html(String)
}

extension MarkdownInline {
    /// Plain-text rendition used for accessibility, copying and alt text.
    var plainText: String {
        switch self {
        case .text(let s), .code(let s), .html(let s): s
        case .emphasis(let c), .strong(let c), .strikethrough(let c), .link(_, let c): c.plainText
        case .image(_, let alt, _): alt
        case .softBreak: " "
        case .lineBreak: "\n"
        case .math(let latex): latex
        case .emoji(let name): ":\(name):"
        }
    }
}

extension [MarkdownInline] {
    var plainText: String {
        var result = ""
        for inline in self { result += inline.plainText }
        return result
    }
}
