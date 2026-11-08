import SwiftUI
import CoreText

/// Typeset code lines (CoreText renderer).
struct CodeLines: @unchecked Sendable {
    var lines: [CTLine]
    var maxWidth: CGFloat
}

/// Prepared code block: highlighted text split into chunks of lines.
///
/// Chunks keep each piece small (SwiftUI lays out a 5 000-line `Text` slowly) and let streaming
/// re-highlight only the last chunk.
struct PreparedCode: Sendable {
    struct Chunk: Sendable, Identifiable {
        let id: Int
        /// SwiftUI `Text` renderer.
        let text: AttributedString?
        /// CoreText renderer.
        let lines: CodeLines?
    }

    var language: String?
    var code: String
    var chunks: [Chunk]
    var isClosed: Bool
    var fontSize: CGFloat
    var lineCount: Int
    /// CoreText metrics: line pitch, ascent, and the widest line.
    var lineHeight: CGFloat = 0
    var ascent: CGFloat = 0
    var contentWidth: CGFloat = 0

    var usesCoreText: Bool { chunks.first?.lines != nil }
}

/// Highlights code into attributed chunks, caching chunks by content, start state, language and theme.
struct CodeHighlighting {
    static let linesPerChunk = 40

    private struct ChunkKey: Hashable, Sendable {
        var text: SourceText
        var state: LexState
        var language: String
        var theme: Int
    }

    private struct Pending {
        var index: Int
        var key: ChunkKey
        var tokens: [HighlightToken]
        var endState: LexState
    }

    private struct ChunkValue: Sendable {
        var text: AttributedString?
        var lines: CodeLines?
        var endState: LexState
    }

    private static let cache = SendableCache<ChunkKey, ChunkValue>(totalCostLimit: 32 << 20)

    static func removeCachedChunks() { cache.removeAll() }

    private static let colorKey = NSAttributedString.Key(AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.name)
    private static let fontKey = NSAttributedString.Key(AttributeScopes.SwiftUIAttributes.FontAttribute.name)

    let theme: ResolvedTheme

    func prepare(_ block: MarkdownCodeBlock) -> PreparedCode {
        let style = theme.theme.codeBlock
        let font = theme.font(style.font, monospaced: true)
        let grammar = LanguageGrammar.lookup(block.language)
        let highlighter = grammar.map(SyntaxHighlighter.init)
        let lines = block.code.split(separator: "\n", omittingEmptySubsequences: false)

        // Pass 1 (sequential, cheap): chunk texts, cache lookups and tokenization of misses, carrying
        // the lexer state across chunks.
        var values: [ChunkValue?] = []
        var pending: [Pending] = []
        var state = LexState.normal
        var index = 0
        while index < lines.count {
            let end = min(index + Self.linesPerChunk, lines.count)
            var text = lines[index..<end].joined(separator: "\n")
            if end < lines.count { text += "\n" }
            let key = ChunkKey(text: SourceText(text), state: state, language: grammar?.name ?? "", theme: theme.fingerprint)
            if let cached = Self.cache[key] {
                values.append(cached)
                state = cached.endState
            } else {
                var tokens: [HighlightToken] = []
                if let highlighter {
                    Self.tokenize(key.text.string, with: highlighter, state: &state, into: &tokens)
                }
                pending.append(Pending(index: values.count, key: key, tokens: tokens, endState: state))
                values.append(nil)
            }
            index = end
        }

        // Pass 2 (parallel for large blocks): attributed strings for the misses.
        let workers = pending.count > 2 ? Parallel.processorCount : 1
        let coreText = theme.textRenderer == .coreText
        let platformFont = theme.platformFont(style.font, monospaced: true)
        let built = Parallel.map(pending.count, workers: workers) { range in
            range.map { i -> ChunkValue in
                let item = pending[i]
                if coreText {
                    return ChunkValue(text: nil, lines: typeset(item.key.text.string, tokens: item.tokens, font: platformFont),
                                      endState: item.endState)
                }
                return ChunkValue(text: attributed(item.key.text.string, tokens: item.tokens, font: font), lines: nil,
                                  endState: item.endState)
            }
        }.flatMap { $0 }
        for (item, value) in zip(pending, built) {
            values[item.index] = value
            Self.cache.set(value, for: item.key, cost: item.key.text.byteCount * 8)
        }
        let chunks = values.enumerated().map { PreparedCode.Chunk(id: $0.offset, text: $0.element?.text, lines: $0.element?.lines) }
        var code = PreparedCode(language: block.language, code: block.code, chunks: chunks, isClosed: block.isClosed,
                                fontSize: theme.size(style.font), lineCount: lines.count)
        if coreText {
            let ascent = ceil(platformFont.ascender)
            let descent = ceil(-platformFont.descender)
            code.ascent = ascent
            code.lineHeight = ascent + descent + ceil(code.fontSize * 0.3)
            code.contentWidth = ceil(chunks.reduce(0) { max($0, $1.lines?.maxWidth ?? 0) })
        }
        return code
    }

    private static let ctFontKey = NSAttributedString.Key(kCTFontAttributeName as String)
    private static let ctColorKey = NSAttributedString.Key(kCTForegroundColorAttributeName as String)

    /// CoreText path: colored attributed string with CoreText attributes, one `CTLine` per source line.
    private func typeset(_ text: String, tokens: [HighlightToken], font: PlatformFont) -> CodeLines {
        let plainColor = theme.codeColors[Int(CodeTokenKind.plain.rawValue)]
        let ns = NSMutableAttributedString(string: text, attributes: [Self.ctFontKey: font, Self.ctColorKey: plainColor.cgColor])
        if !tokens.isEmpty {
            let boldKeywords = theme.theme.codeBlock.theme.boldKeywords
            let boldFont = boldKeywords ? theme.platformFont(theme.theme.codeBlock.font, bold: true, monospaced: true) : font
            var text = text
            text.makeContiguousUTF8()
            text.utf8.withContiguousStorageIfAvailable { bytes in
                var utf16 = 0
                var byte = 0
                func advance(to target: Int) {
                    while byte < target {
                        let b = bytes[byte]
                        if b & 0xC0 != 0x80 { utf16 += b >= 0xF0 ? 2 : 1 }
                        byte += 1
                    }
                }
                var colors: [CodeTokenKind: CGColor] = [:]
                for token in tokens where token.start >= byte && token.kind != .plain {
                    let color = theme.codeColors[Int(token.kind.rawValue)]
                    guard color != plainColor || (boldKeywords && token.kind == .keyword) else { continue }
                    advance(to: token.start)
                    let start = utf16
                    advance(to: token.end)
                    let range = NSRange(location: start, length: utf16 - start)
                    let cgColor = colors[token.kind] ?? color.cgColor
                    colors[token.kind] = cgColor
                    ns.addAttribute(Self.ctColorKey, value: cgColor, range: range)
                    if boldKeywords && token.kind == .keyword { ns.addAttribute(Self.ctFontKey, value: boldFont, range: range) }
                }
            }
        }
        let typesetter = CTTypesetterCreateWithAttributedString(ns)
        let string = ns.string as NSString
        var lines: [CTLine] = []
        var maxWidth: CGFloat = 0
        var location = 0
        let length = string.length
        // A zero-length CFRange means "to the end of the string" to CoreText, so empty lines get their own
        // empty CTLine instead of a zero-length range (which would draw the rest of the code).
        let emptyLine = CTLineCreateWithAttributedString(NSAttributedString(string: "", attributes: [Self.ctFontKey: font]))
        while location <= length {
            let lineRange = string.lineRange(for: NSRange(location: min(location, max(length - 1, 0)), length: 0))
            if length == 0 { lines.append(emptyLine); break }
            var contentLength = lineRange.length
            // Exclude the trailing newline.
            if contentLength > 0, NSMaxRange(lineRange) <= length,
               string.character(at: NSMaxRange(lineRange) - 1) == 0x0A { contentLength -= 1 }
            let line = contentLength > 0
                ? CTTypesetterCreateLine(typesetter, CFRange(location: lineRange.location, length: contentLength))
                : emptyLine
            lines.append(line)
            maxWidth = max(maxWidth, CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
            location = NSMaxRange(lineRange)
            if location >= length { break }
        }
        return CodeLines(lines: lines, maxWidth: maxWidth)
    }

    @inline(never)
    private static func tokenize(_ text: String, with highlighter: SyntaxHighlighter, state: inout LexState,
                                 into tokens: inout [HighlightToken]) {
        var copy = text
        copy.makeContiguousUTF8()
        var newState = state
        var newTokens: [HighlightToken] = []
        copy.utf8.withContiguousStorageIfAvailable { bytes in
            let result = highlighter.tokenize(bytes, state: newState)
            newTokens = result.tokens
            newState = result.state
        }
        tokens = newTokens
        state = newState
    }

    private func attributed(_ text: String, tokens: [HighlightToken], font: Font) -> AttributedString {
        let plainColor = theme.codeColors[Int(CodeTokenKind.plain.rawValue)]
        guard !tokens.isEmpty else {
            var attributed = AttributedString(text)
            attributed.font = font
            attributed.foregroundColor = Color(plainColor)
            return attributed
        }
        let boldKeywords = theme.theme.codeBlock.theme.boldKeywords
        let boldFont = boldKeywords ? theme.font(theme.theme.codeBlock.font, bold: true, monospaced: true) : font
        var text = text
        text.makeContiguousUTF8()
        return text.utf8.withContiguousStorageIfAvailable { bytes -> AttributedString in
            // Building through NSAttributedString (UTF-16 ranges) and converting once is ~5× faster
            // than appending thousands of AttributedString runs.
            let ns = NSMutableAttributedString(string: text, attributes: [Self.fontKey: font, Self.colorKey: Color(plainColor)])
            var utf16 = 0
            var byte = 0
            @inline(__always) func advance(to target: Int) {
                while byte < target {
                    let b = bytes[byte]
                    if b & 0xC0 != 0x80 { utf16 += b >= 0xF0 ? 2 : 1 }
                    byte += 1
                }
            }
            var colorCache: [CodeTokenKind: Color] = [:]
            for token in tokens where token.start >= byte && token.kind != .plain {
                let color = theme.codeColors[Int(token.kind.rawValue)]
                guard color != plainColor || (boldKeywords && token.kind == .keyword) else { continue }
                advance(to: token.start)
                let start = utf16
                advance(to: token.end)
                let range = NSRange(location: start, length: utf16 - start)
                let swiftUIColor = colorCache[token.kind] ?? Color(color)
                colorCache[token.kind] = swiftUIColor
                ns.addAttribute(Self.colorKey, value: swiftUIColor, range: range)
                if boldKeywords && token.kind == .keyword { ns.addAttribute(Self.fontKey, value: boldFont, range: range) }
            }
            return (try? AttributedString(ns, including: \.swiftUI)) ?? AttributedString(text)
        } ?? AttributedString(text)
    }
}
