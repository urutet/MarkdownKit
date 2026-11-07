import Foundation
import Markdown

/// Result of parsing a Markdown source string.
struct ParseResult: Sendable {
    var blocks: [MarkdownBlock]
    /// UTF-8 offset, in the parsed source, where the last top-level block starts.
    /// Used by the incremental (streaming) parser to re-parse only the tail.
    var lastBlockStart: Int?
}

/// Abstraction over Markdown parser implementations so alternatives can be benchmarked side by side.
protocol MarkdownParsing: Sendable {
    func parse(_ source: String) -> ParseResult
}

/// Options that control parsing.
public struct MarkdownParseOptions: Hashable, Sendable {
    /// Recognize TeX math: `$…$`, `$$…$$`, `\(…\)` and `\[…\]`.
    public var math: Bool
    /// Recognize `:shortcode:` custom emoji.
    public var customEmoji: Bool

    public init(math: Bool = true, customEmoji: Bool = true) {
        self.math = math
        self.customEmoji = customEmoji
    }

    public static let `default` = MarkdownParseOptions()
}

/// Parses Markdown into ``MarkdownDocument`` using apple/swift-markdown (cmark-gfm).
public struct MarkdownParser: MarkdownParsing {
    public var options: MarkdownParseOptions

    public init(options: MarkdownParseOptions = .default) {
        self.options = options
    }

    public func parseDocument(_ source: String) -> MarkdownDocument {
        MarkdownDocument(blocks: parse(source).blocks)
    }

    func parse(_ source: String) -> ParseResult {
        let pre: MathPreprocessor.Result = options.math
            ? MathPreprocessor.process(source)
            : .init(text: source, spans: [], offsets: OffsetMap())
        let document = Document(parsing: pre.text)
        var converter = Converter(math: pre.spans, emoji: options.customEmoji, source: pre.text)
        var blocks: [MarkdownBlock] = []
        var lastStart: Int?
        for child in document.children {
            if let range = child.range {
                lastStart = pre.offsets.sourceOffset(forPreprocessed: converter.lines.offset(of: range.lowerBound))
            }
            converter.appendBlock(child, to: &blocks)
        }
        return ParseResult(blocks: blocks, lastBlockStart: lastStart)
    }
}

/// Lazily computed table of line start offsets (UTF-8).
struct LineTable {
    private let utf8: String.UTF8View
    private var starts: [Int] = [0]
    private var scanned = 0
    private var scanIndex: String.UTF8View.Index

    init(_ text: String) {
        utf8 = text.utf8
        scanIndex = utf8.startIndex
    }

    /// Byte offset of a 1-based line/column location.
    mutating func offset(of location: SourceLocation) -> Int {
        let line = max(location.line, 1)
        while starts.count < line, scanIndex < utf8.endIndex {
            let byte = utf8[scanIndex]
            utf8.formIndex(after: &scanIndex)
            scanned += 1
            if byte == UInt8(ascii: "\n") { starts.append(scanned) }
        }
        let base = line - 1 < starts.count ? starts[line - 1] : scanned
        return base + max(location.column - 1, 0)
    }

    mutating func line(_ number: Int) -> Substring.UTF8View? {
        _ = offset(of: SourceLocation(line: number + 1, column: 1, source: nil))
        guard number - 1 < starts.count else { return nil }
        let start = utf8.index(utf8.startIndex, offsetBy: starts[number - 1])
        var end = start
        while end < utf8.endIndex, utf8[end] != UInt8(ascii: "\n") { utf8.formIndex(after: &end) }
        return Substring(utf8[start..<end]).utf8
    }
}

private struct Converter {
    let math: [MathSpan]
    let emoji: Bool
    var lines: LineTable

    init(math: [MathSpan], emoji: Bool, source: String) {
        self.math = math
        self.emoji = emoji
        self.lines = LineTable(source)
    }

    mutating func appendBlock(_ markup: Markup, to blocks: inout [MarkdownBlock]) {
        switch markup {
        case let paragraph as Paragraph:
            appendParagraph(inlines(paragraph.children), to: &blocks)
        case let heading as Heading:
            blocks.append(.heading(level: heading.level, inlines(heading.children)))
        case let quote as BlockQuote:
            blocks.append(.blockquote(convertBlocks(quote.children)))
        case let list as OrderedList:
            blocks.append(.list(convertList(list.listItems, ordered: true, start: Int(list.startIndex))))
        case let list as UnorderedList:
            blocks.append(.list(convertList(list.listItems, ordered: false, start: 1)))
        case let code as CodeBlock:
            var source = code.code
            if source.hasSuffix("\n") { source.removeLast() }
            let language = code.language.flatMap { $0.isEmpty ? nil : $0 }
            blocks.append(.codeBlock(MarkdownCodeBlock(language: language, code: restoreMath(in: source), isClosed: isFenceClosed(code))))
        case let table as Markdown.Table:
            blocks.append(.table(convertTable(table)))
        case is ThematicBreak:
            blocks.append(.thematicBreak)
        case let html as HTMLBlock:
            blocks.append(.htmlBlock(restoreMath(in: html.rawHTML)))
        default:
            // Unknown containers: flatten their block children.
            for child in markup.children { appendBlock(child, to: &blocks) }
        }
    }

    mutating func convertBlocks(_ children: MarkupChildren) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        for child in children { appendBlock(child, to: &blocks) }
        return blocks
    }

    /// Splits a paragraph around display math so formulas become their own blocks.
    func appendParagraph(_ inlines: [MarkdownInline], to blocks: inout [MarkdownBlock]) {
        guard inlines.contains(where: { if case .math = $0 { return true }; return false }) else {
            if !inlines.isEmpty { blocks.append(.paragraph(inlines)) }
            return
        }
        var current: [MarkdownInline] = []
        func flush() {
            while let last = current.last, last == .softBreak || last == .lineBreak { current.removeLast() }
            while let first = current.first, first == .softBreak || first == .lineBreak { current.removeFirst() }
            if !current.isEmpty { blocks.append(.paragraph(current)) }
            current.removeAll()
        }
        for inline in inlines {
            if case .math(let latex) = inline, displayMath.contains(latex) {
                flush()
                blocks.append(.mathBlock(latex))
            } else {
                current.append(inline)
            }
        }
        flush()
    }

    private var displayMath: Set<String> {
        Set(math.lazy.filter(\.isDisplay).map(\.latex))
    }

    mutating func convertList(_ items: LazyMapSequence<MarkupChildren, ListItem>, ordered: Bool, start: Int) -> MarkdownList {
        var result: [MarkdownListItem] = []
        var isTight = true
        var previousEnd: Int?
        for item in items {
            if let range = item.range {
                if previousEnd != nil, range.lowerBound.line > 1,
                   let before = lines.line(range.lowerBound.line - 1),
                   before.allSatisfy({ $0 == UInt8(ascii: " ") || $0 == UInt8(ascii: "\t") || $0 == UInt8(ascii: ">") }) {
                    isTight = false
                }
                previousEnd = range.upperBound.line
            }
            let checkbox: Bool? = switch item.checkbox {
            case .checked: true
            case .unchecked: false
            case nil: nil
            }
            result.append(MarkdownListItem(checkbox: checkbox, blocks: convertBlocks(item.children)))
        }
        return MarkdownList(isOrdered: ordered, startIndex: start, isTight: isTight, items: result)
    }

    func convertTable(_ table: Markdown.Table) -> MarkdownTable {
        let alignments: [MarkdownTable.Alignment] = table.columnAlignments.map {
            switch $0 {
            case .left: .left
            case .center: .center
            case .right: .right
            case nil: .none
            }
        }
        let header = table.head.cells.map { inlines($0.children) }
        let rows = table.body.rows.map { row in Array(row.cells.map { inlines($0.children) }) }
        return MarkdownTable(alignments: alignments, header: Array(header), rows: Array(rows))
    }

    mutating func isFenceClosed(_ code: CodeBlock) -> Bool {
        guard let range = code.range, let first = lines.line(range.lowerBound.line) else { return true }
        let fenceChars = first.drop(while: { $0 == UInt8(ascii: " ") || $0 == UInt8(ascii: ">") || $0 == UInt8(ascii: "\t") })
        guard let fenceChar = fenceChars.first, fenceChar == UInt8(ascii: "`") || fenceChar == UInt8(ascii: "~") else {
            return true // Indented code block.
        }
        let fenceLength = fenceChars.prefix(while: { $0 == fenceChar }).count
        guard range.upperBound.line > range.lowerBound.line,
              let last = lines.line(range.upperBound.line) else { return false }
        let trimmed = last.drop(while: { $0 == UInt8(ascii: " ") || $0 == UInt8(ascii: ">") || $0 == UInt8(ascii: "\t") })
        let count = trimmed.prefix(while: { $0 == fenceChar }).count
        return count >= fenceLength && trimmed.dropFirst(count).allSatisfy { $0 == UInt8(ascii: " ") || $0 == UInt8(ascii: "\t") }
    }

    // MARK: Inlines

    func inlines(_ children: MarkupChildren) -> [MarkdownInline] {
        var result: [MarkdownInline] = []
        for child in children { appendInline(child, to: &result) }
        return result
    }

    func appendInline(_ markup: Markup, to result: inout [MarkdownInline]) {
        switch markup {
        case let text as Markdown.Text:
            appendText(text.string, to: &result)
        case let emphasis as Emphasis:
            result.append(.emphasis(inlines(emphasis.children)))
        case let strong as Strong:
            result.append(.strong(inlines(strong.children)))
        case let strike as Strikethrough:
            result.append(.strikethrough(inlines(strike.children)))
        case let code as InlineCode:
            result.append(.code(restoreMath(in: code.code)))
        case let link as Markdown.Link:
            result.append(.link(destination: link.destination, inlines(link.children)))
        case let image as Markdown.Image:
            let alt = inlines(image.children).plainText
            result.append(.image(source: image.source, alt: alt, title: image.title))
        case is SoftBreak:
            result.append(.softBreak)
        case is LineBreak:
            result.append(.lineBreak)
        case let html as InlineHTML:
            let raw = html.rawHTML.lowercased().filter { !$0.isWhitespace }
            if raw == "<br>" || raw == "<br/>" {
                result.append(.lineBreak)
            } else {
                result.append(.html(html.rawHTML))
            }
        case let symbol as SymbolLink:
            result.append(.code(symbol.destination ?? ""))
        default:
            for child in markup.children { appendInline(child, to: &result) }
        }
    }

    /// Splits text into plain text, math placeholders and `:emoji:` shortcodes.
    func appendText(_ string: String, to result: inout [MarkdownInline]) {
        let hasMath = !math.isEmpty && string.unicodeScalars.contains(MathPreprocessor.openScalar)
        let hasColon = emoji && string.utf8.contains(UInt8(ascii: ":"))
        guard hasMath || hasColon else {
            appendPlain(string, to: &result)
            return
        }
        let scalars = string.unicodeScalars
        var plainStart = scalars.startIndex
        var index = scalars.startIndex
        while index < scalars.endIndex {
            let scalar = scalars[index]
            if hasMath, scalar == MathPreprocessor.openScalar,
               let close = scalars[index...].firstIndex(of: MathPreprocessor.closeScalar),
               let spanIndex = Int(String(scalars[scalars.index(after: index)..<close])),
               spanIndex < math.count {
                appendPlain(String(scalars[plainStart..<index]), to: &result)
                result.append(.math(math[spanIndex].latex))
                index = scalars.index(after: close)
                plainStart = index
                continue
            }
            if hasColon, scalar == ":", let end = emojiEnd(in: scalars, after: index) {
                let name = String(scalars[scalars.index(after: index)..<end])
                appendPlain(String(scalars[plainStart..<index]), to: &result)
                result.append(.emoji(name))
                index = scalars.index(after: end)
                plainStart = index
                continue
            }
            index = scalars.index(after: index)
        }
        appendPlain(String(scalars[plainStart..<scalars.endIndex]), to: &result)
    }

    private func emojiEnd(in scalars: String.UnicodeScalarView, after colon: String.UnicodeScalarView.Index) -> String.UnicodeScalarView.Index? {
        var index = scalars.index(after: colon)
        guard index < scalars.endIndex, scalars[index].properties.isAlphabetic, scalars[index].isASCII else { return nil }
        var length = 0
        while index < scalars.endIndex {
            let s = scalars[index]
            if s == ":" { return length > 0 ? index : nil }
            guard s.isASCII, s.properties.isAlphabetic || ("0"..."9").contains(s) || s == "_" || s == "-" || s == "+" else { return nil }
            length += 1
            if length > 64 { return nil }
            index = scalars.index(after: index)
        }
        return nil
    }

    private func appendPlain(_ string: String, to result: inout [MarkdownInline]) {
        guard !string.isEmpty else { return }
        if case .text(let previous) = result.last {
            result[result.count - 1] = .text(previous + string)
        } else {
            result.append(.text(string))
        }
    }

    /// Restores original TeX source for placeholders inside code (which should show raw text).
    func restoreMath(in string: String) -> String {
        guard !math.isEmpty, string.unicodeScalars.contains(MathPreprocessor.openScalar) else { return string }
        var output = ""
        var inlines: [MarkdownInline] = []
        appendText(string, to: &inlines)
        for inline in inlines {
            switch inline {
            case .math(let latex):
                let span = math.first { $0.latex == latex }
                output += span?.isDisplay == true ? "$$\(latex)$$" : "$\(latex)$"
            case .emoji(let name): output += ":\(name):"
            case .text(let s): output += s
            default: break
            }
        }
        return output
    }
}
