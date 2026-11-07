import Foundation

/// Incremental parser for streamed text.
///
/// Keeps the result of the previous parse; when new text arrives that extends the previous text,
/// every top-level block before the last one is frozen and reused, and only the tail (starting at
/// the last block) is re-parsed. Cost per update is proportional to the size of the last block,
/// not the whole message.
///
/// Not thread-safe: use from one task at a time.
final class IncrementalParser {
    private let parser: any MarkdownParsing
    private var source: [UInt8] = []
    private var frozen: [MarkdownBlock] = []
    private var tailStart = 0

    private(set) var reparsedBytes = 0

    init(parser: any MarkdownParsing = MarkdownParser()) {
        self.parser = parser
    }

    func reset() {
        source = []
        frozen = []
        tailStart = 0
    }

    /// Parses `text`, reusing previous work when `text` shares the frozen prefix with the previous input.
    ///
    /// - Parameter isStreaming: `true` while more text is expected. Enables display repairs for
    ///   incomplete constructs (unclosed `**`/`` ` ``/`~~`, partial table rows).
    func update(_ text: String, isStreaming: Bool) -> [MarkdownBlock] {
        let bytes = Array(text.utf8)
        if !(tailStart > 0 && bytes.count >= tailStart && Self.prefixEqual(bytes, source, count: tailStart)) {
            frozen = []
            tailStart = 0
        }
        source = bytes
        let tailBytes = bytes[tailStart...]
        var tail = String(decoding: tailBytes, as: UTF8.self)
        var hidesLastParagraph = false
        if isStreaming {
            (tail, hidesLastParagraph) = StreamingRepair.repair(tail)
        }
        reparsedBytes = tail.utf8.count
        let result = parser.parse(tail)
        var tailBlocks = result.blocks
        if hidesLastParagraph, case .paragraph = tailBlocks.last {
            tailBlocks.removeLast()
        }
        let blocks = frozen + tailBlocks

        // Freeze everything before the last block of this parse.
        if let lastStart = result.lastBlockStart, result.blocks.count > 1 {
            frozen += result.blocks.dropLast()
            tailStart += min(lastStart, tailBytes.count)
        }
        return blocks
    }

    private static func prefixEqual(_ a: [UInt8], _ b: [UInt8], count: Int) -> Bool {
        guard a.count >= count, b.count >= count else { return false }
        return a.withUnsafeBufferPointer { pa in
            b.withUnsafeBufferPointer { pb in
                memcmp(pa.baseAddress!, pb.baseAddress!, count) == 0
            }
        }
    }
}

/// Display-only fixes for incomplete Markdown at the end of a stream.
enum StreamingRepair {
    /// Returns the repaired tail and whether a trailing paragraph that is really an incomplete table
    /// header should be hidden.
    static func repair(_ tail: String) -> (String, hidesLastParagraph: Bool) {
        var lines = tail.split(separator: "\n", omittingEmptySubsequences: false)
        guard !lines.isEmpty else { return (tail, false) }

        // Track fences; an open fence renders as an in-progress code block: leave untouched.
        var inFence = false
        var fence: Substring = ""
        var lastBlankLine = -1
        var blankCandidate = -1
        for (index, line) in lines.enumerated() {
            let trimmed = line.drop(while: { $0 == " " || $0 == ">" })
            if inFence {
                if trimmed.hasPrefix(fence) && trimmed.drop(while: { $0 == fence.first }).allSatisfy(\.isWhitespace) {
                    inFence = false
                }
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let char = trimmed.first!
                fence = trimmed.prefix(while: { $0 == char })
                inFence = true
                continue
            }
            if line.allSatisfy(\.isWhitespace) {
                if index < lines.count - 1 || lastBlankLine < 0 { blankCandidate = index }
            } else {
                lastBlankLine = blankCandidate
            }
        }
        if inFence { return (tail, false) }

        var changed = false
        // Partial table row: hide until its newline arrives.
        if let last = lines.last, !last.isEmpty, last.drop(while: { $0 == " " }).hasPrefix("|") {
            lines.removeLast()
            changed = true
        }

        // A paragraph made only of `|` lines is a table header waiting for its delimiter row.
        let paragraphLines = lines[(lastBlankLine + 1)...].filter { !$0.allSatisfy(\.isWhitespace) }
        let hides = !paragraphLines.isEmpty
            && paragraphLines.allSatisfy { $0.drop(while: { $0 == " " }).hasPrefix("|") }
            && !paragraphLines.contains(where: { $0.contains("-") && $0.allSatisfy { "|-: ".contains($0) } })

        // Close dangling inline markers in the last paragraph.
        var suffix = ""
        if let lastLine = lines.last, !lastLine.allSatisfy(\.isWhitespace) {
            let paragraph = lines[(lastBlankLine + 1)...].joined(separator: "\n")
            var backticks = 0, strong = 0, strike = 0
            var index = paragraph.startIndex
            var inCode = false
            while index < paragraph.endIndex {
                let c = paragraph[index]
                if c == "\\" {
                    index = paragraph.index(after: index)
                    if index < paragraph.endIndex { index = paragraph.index(after: index) }
                    continue
                }
                let next = paragraph.index(after: index)
                if c == "`" {
                    backticks += 1
                    inCode.toggle()
                } else if !inCode, c == "*", next < paragraph.endIndex, paragraph[next] == "*" {
                    strong += 1
                    index = paragraph.index(after: next)
                    continue
                } else if !inCode, c == "~", next < paragraph.endIndex, paragraph[next] == "~" {
                    strike += 1
                    index = paragraph.index(after: next)
                    continue
                }
                index = next
            }
            if backticks % 2 == 1 { suffix += "`" }
            if strike % 2 == 1 { suffix += "~~" }
            if strong % 2 == 1 {
                // Avoid `****` when the text ends right after an opening marker.
                if paragraph.hasSuffix("**") { lines[lines.count - 1].removeLast(2) } else { suffix += "**" }
                changed = true
            }
        }
        if suffix.isEmpty && !changed { return (tail, hides) }
        return (lines.joined(separator: "\n") + suffix, hides)
    }
}
