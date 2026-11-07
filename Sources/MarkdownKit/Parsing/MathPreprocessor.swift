import Foundation

/// A math expression extracted from the source before Markdown parsing.
struct MathSpan: Hashable, Sendable {
    var latex: String
    var isDisplay: Bool
}

/// Extracts TeX math (`$…$`, `$$…$$`, `\(…\)`, `\[…\]`) from Markdown source and replaces it with
/// private-use placeholders, so that the Markdown parser doesn't interpret `_`, `*`, `\` or `|`
/// inside formulas. Code spans and fenced code blocks are left untouched.
///
/// Works on UTF-8 bytes in a single pass.
struct MathPreprocessor {
    struct Result {
        var text: String
        var spans: [MathSpan]
        var offsets: OffsetMap
    }

    // Placeholder: U+E000 <decimal index> U+E001
    static let openMarker: [UInt8] = [0xEE, 0x80, 0x80]
    static let closeMarker: [UInt8] = [0xEE, 0x80, 0x81]
    static let openScalar: Unicode.Scalar = "\u{E000}"
    static let closeScalar: Unicode.Scalar = "\u{E001}"

    static func process(_ source: String) -> Result {
        var utf8 = Array(source.utf8)
        // Fast path: nothing that can start math.
        if !utf8.contains(UInt8(ascii: "$")) && !utf8.contains(UInt8(ascii: "\\")) {
            return Result(text: source, spans: [], offsets: OffsetMap())
        }
        var processor = MathPreprocessor(bytes: utf8)
        processor.run()
        if processor.spans.isEmpty {
            return Result(text: source, spans: [], offsets: OffsetMap())
        }
        utf8 = processor.output
        return Result(text: String(decoding: utf8, as: UTF8.self), spans: processor.spans, offsets: processor.offsets)
    }

    private let bytes: [UInt8]
    private var output: [UInt8] = []
    private var spans: [MathSpan] = []
    private var offsets = OffsetMap()
    private var i = 0

    private init(bytes: [UInt8]) {
        self.bytes = bytes
        output.reserveCapacity(bytes.count)
    }

    private static let backtick = UInt8(ascii: "`")
    private static let tilde = UInt8(ascii: "~")
    private static let dollar = UInt8(ascii: "$")
    private static let backslash = UInt8(ascii: "\\")
    private static let newline = UInt8(ascii: "\n")
    private static let space = UInt8(ascii: " ")
    private static let tab = UInt8(ascii: "\t")

    private mutating func run() {
        let n = bytes.count
        var atLineStart = true
        while i < n {
            if atLineStart, let fenceEnd = fencedBlockEnd(from: i) {
                output.append(contentsOf: bytes[i..<fenceEnd])
                i = fenceEnd
                atLineStart = true
                continue
            }
            atLineStart = false
            let b = bytes[i]
            switch b {
            case Self.newline:
                output.append(b)
                i += 1
                atLineStart = true
            case Self.backtick:
                copyCodeSpan()
            case Self.backslash:
                handleBackslash()
            case Self.dollar:
                handleDollar()
            default:
                output.append(b)
                i += 1
            }
        }
    }

    // MARK: Code

    /// If a fenced code block opens at `start` (a line start), returns the index after its closing fence
    /// line (or the end of input for an unterminated fence).
    private func fencedBlockEnd(from start: Int) -> Int? {
        let n = bytes.count
        var j = start
        // Allow indentation and blockquote markers before the fence.
        while j < n, bytes[j] == Self.space || bytes[j] == Self.tab || bytes[j] == UInt8(ascii: ">") { j += 1 }
        guard j < n, bytes[j] == Self.backtick || bytes[j] == Self.tilde else { return nil }
        let fenceChar = bytes[j]
        var fenceLength = 0
        while j < n, bytes[j] == fenceChar { fenceLength += 1; j += 1 }
        guard fenceLength >= 3 else { return nil }
        // Backtick fences can't contain backticks in the info string.
        var k = j
        while k < n, bytes[k] != Self.newline {
            if fenceChar == Self.backtick && bytes[k] == Self.backtick { return nil }
            k += 1
        }
        // Scan following lines for the closing fence.
        var lineStart = k < n ? k + 1 : n
        while lineStart < n {
            var p = lineStart
            while p < n, bytes[p] == Self.space || bytes[p] == Self.tab || bytes[p] == UInt8(ascii: ">") { p += 1 }
            var count = 0
            while p < n, bytes[p] == fenceChar { count += 1; p += 1 }
            var lineEnd = p
            while lineEnd < n, bytes[lineEnd] != Self.newline { lineEnd += 1 }
            if count >= fenceLength {
                var onlySpaces = true
                var q = p
                while q < lineEnd { if bytes[q] != Self.space && bytes[q] != Self.tab { onlySpaces = false; break }; q += 1 }
                if onlySpaces { return lineEnd < n ? lineEnd + 1 : n }
            }
            lineStart = lineEnd < n ? lineEnd + 1 : n
        }
        return n
    }

    private mutating func copyCodeSpan() {
        let n = bytes.count
        var j = i
        while j < n, bytes[j] == Self.backtick { j += 1 }
        let runLength = j - i
        // Find a closing run of the same length, not crossing a blank line.
        var k = j
        while k < n {
            if bytes[k] == Self.newline, k + 1 < n, bytes[k + 1] == Self.newline { break }
            if bytes[k] == Self.backtick {
                var e = k
                while e < n, bytes[e] == Self.backtick { e += 1 }
                if e - k == runLength {
                    output.append(contentsOf: bytes[i..<e])
                    i = e
                    return
                }
                k = e
            } else {
                k += 1
            }
        }
        output.append(contentsOf: bytes[i..<j])
        i = j
    }

    // MARK: Math

    private mutating func handleBackslash() {
        let n = bytes.count
        guard i + 1 < n else { output.append(bytes[i]); i += 1; return }
        let next = bytes[i + 1]
        if next == UInt8(ascii: "(") || next == UInt8(ascii: "[") {
            let isDisplay = next == UInt8(ascii: "[")
            let closer: UInt8 = isDisplay ? UInt8(ascii: "]") : UInt8(ascii: ")")
            if let end = find(closingBackslash: closer, from: i + 2, allowNewlines: isDisplay) {
                emit(latexFrom: i + 2, to: end, isDisplay: isDisplay, consumedUntil: end + 2)
                return
            }
        }
        // Regular escape: copy both bytes so `\$` stays literal.
        output.append(bytes[i])
        output.append(next)
        i += 2
    }

    private mutating func handleDollar() {
        let n = bytes.count
        if i + 1 < n, bytes[i + 1] == Self.dollar {
            if let end = find(doubleDollarFrom: i + 2) {
                emit(latexFrom: i + 2, to: end, isDisplay: true, consumedUntil: end + 2)
                return
            }
            output.append(contentsOf: [Self.dollar, Self.dollar])
            i += 2
            return
        }
        if let end = find(inlineDollarCloseFrom: i + 1) {
            emit(latexFrom: i + 1, to: end, isDisplay: false, consumedUntil: end + 1)
            return
        }
        output.append(Self.dollar)
        i += 1
    }

    private func find(closingBackslash closer: UInt8, from start: Int, allowNewlines: Bool) -> Int? {
        let n = bytes.count
        var k = start
        while k + 1 < n {
            let b = bytes[k]
            if b == Self.newline {
                if !allowNewlines { return nil }
                if k + 1 < n, bytes[k + 1] == Self.newline { return nil }
            }
            if b == Self.backslash {
                if bytes[k + 1] == closer { return k > start ? k : nil }
                k += 2
                continue
            }
            k += 1
        }
        return nil
    }

    private func find(doubleDollarFrom start: Int) -> Int? {
        let n = bytes.count
        var k = start
        while k + 1 < n {
            let b = bytes[k]
            if b == Self.backslash { k += 2; continue }
            if b == Self.dollar && bytes[k + 1] == Self.dollar { return k > start ? k : nil }
            // A blank line or a code fence ends the search.
            if b == Self.newline, k + 1 < n, bytes[k + 1] == Self.newline { return nil }
            k += 1
        }
        return nil
    }

    private func find(inlineDollarCloseFrom start: Int) -> Int? {
        let n = bytes.count
        guard start < n else { return nil }
        let first = bytes[start]
        // Opening `$` must be followed by a non-space character.
        if first == Self.space || first == Self.tab || first == Self.newline || first == Self.dollar { return nil }
        var k = start
        while k < n {
            let b = bytes[k]
            if b == Self.newline { return nil }
            if b == Self.backslash { k += 2; continue }
            if b == Self.dollar {
                let prev = bytes[k - 1]
                let nextIsDigit = k + 1 < n && bytes[k + 1] >= UInt8(ascii: "0") && bytes[k + 1] <= UInt8(ascii: "9")
                if prev != Self.space && prev != Self.tab && !nextIsDigit && k > start {
                    return k
                }
                if nextIsDigit { return nil } // Looks like currency: "$5 and $10".
            }
            k += 1
        }
        return nil
    }

    private mutating func emit(latexFrom start: Int, to end: Int, isDisplay: Bool, consumedUntil: Int) {
        let latex = String(decoding: bytes[start..<end], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !latex.isEmpty else {
            output.append(contentsOf: bytes[i..<consumedUntil])
            i = consumedUntil
            return
        }
        offsets.add(preprocessed: output.count, source: i)
        let index = spans.count
        spans.append(MathSpan(latex: latex, isDisplay: isDisplay))
        output.append(contentsOf: Self.openMarker)
        output.append(contentsOf: Array(String(index).utf8))
        output.append(contentsOf: Self.closeMarker)
        i = consumedUntil
        offsets.add(preprocessed: output.count, source: i)
    }
}

/// Maps UTF-8 offsets in preprocessed text back to offsets in the original source.
struct OffsetMap: Sendable {
    private var preprocessed: [Int] = []
    private var source: [Int] = []

    mutating func add(preprocessed p: Int, source s: Int) {
        preprocessed.append(p)
        source.append(s)
    }

    func sourceOffset(forPreprocessed offset: Int) -> Int {
        guard !preprocessed.isEmpty else { return offset }
        // Binary search for the last anchor <= offset.
        var low = 0, high = preprocessed.count - 1, found = -1
        while low <= high {
            let mid = (low + high) / 2
            if preprocessed[mid] <= offset { found = mid; low = mid + 1 } else { high = mid - 1 }
        }
        guard found >= 0 else { return offset }
        // Odd anchors close a placeholder; even anchors open one (offsets inside map to its start).
        if found % 2 == 0 {
            return source[found]
        }
        return source[found] + (offset - preprocessed[found])
    }
}
