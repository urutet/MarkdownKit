import Foundation

/// A highlighted range, in UTF-8 byte offsets relative to the tokenized text.
struct HighlightToken: Equatable {
    var start: Int
    var end: Int
    var kind: CodeTokenKind
}

/// Lexer state carried across lines (multi-line comments and strings).
enum LexState: Hashable, Sendable {
    case normal
    case blockComment(Int)
    case string(UInt8, triple: Bool)
}

/// Single-pass, allocation-light syntax highlighter driven by a ``LanguageGrammar``.
///
/// Works on UTF-8 bytes line by line, carrying ``LexState`` between lines so a chunk of lines can be
/// highlighted independently given its starting state.
struct SyntaxHighlighter: Sendable {
    let grammar: LanguageGrammar
    private let lineComments: [[UInt8]]
    private let blockComments: [([UInt8], [UInt8])]

    init(grammar: LanguageGrammar) {
        self.grammar = grammar
        lineComments = grammar.lineComments.map { Array($0.utf8) }
        blockComments = grammar.blockComments.map { (Array($0.open.utf8), Array($0.close.utf8)) }
    }

    /// Tokenizes `bytes`, starting in `state`, and returns tokens and the state after the last line.
    func tokenize(_ bytes: UnsafeBufferPointer<UInt8>, state initial: LexState) -> (tokens: [HighlightToken], state: LexState) {
        var tokens: [HighlightToken] = []
        tokens.reserveCapacity(bytes.count / 4)
        var state = initial
        var lineStart = 0
        let count = bytes.count
        while lineStart <= count {
            var lineEnd = lineStart
            while lineEnd < count, bytes[lineEnd] != Self.newline { lineEnd += 1 }
            tokenizeLine(bytes, from: lineStart, to: lineEnd, state: &state, into: &tokens)
            if lineEnd >= count { break }
            lineStart = lineEnd + 1
        }
        return (tokens, state)
    }

    // MARK: Character classes

    private static let newline = UInt8(ascii: "\n")
    private static let backslash = UInt8(ascii: "\\")

    @inline(__always) private static func isAlpha(_ b: UInt8) -> Bool {
        (b >= 0x61 && b <= 0x7A) || (b >= 0x41 && b <= 0x5A) || b == 0x5F || b >= 0x80
    }
    @inline(__always) private static func isDigit(_ b: UInt8) -> Bool { b >= 0x30 && b <= 0x39 }
    @inline(__always) private static func isUpper(_ b: UInt8) -> Bool { b >= 0x41 && b <= 0x5A }
    @inline(__always) private static func isSpace(_ b: UInt8) -> Bool { b == 0x20 || b == 0x09 || b == 0x0D }
    @inline(__always) private func isIdentifier(_ b: UInt8) -> Bool {
        Self.isAlpha(b) || Self.isDigit(b) || grammar.identifierExtras.contains(b)
    }

    private static let operatorBytes: Set<UInt8> = Set("+-*/%=<>!&|^~?:".utf8)

    @inline(__always)
    private func matches(_ bytes: UnsafeBufferPointer<UInt8>, _ index: Int, _ end: Int, _ pattern: [UInt8]) -> Bool {
        guard index + pattern.count <= end else { return false }
        for (offset, byte) in pattern.enumerated() where bytes[index + offset] != byte { return false }
        return true
    }

    private func word(_ bytes: UnsafeBufferPointer<UInt8>, _ start: Int, _ end: Int) -> String {
        String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<end]), as: UTF8.self)
    }

    // MARK: Lines

    private func tokenizeLine(_ bytes: UnsafeBufferPointer<UInt8>, from start: Int, to end: Int,
                              state: inout LexState, into tokens: inout [HighlightToken]) {
        switch grammar.mode {
        case .diff:
            guard start < end else { return }
            let kind: CodeTokenKind? = switch bytes[start] {
            case UInt8(ascii: "+"): .string
            case UInt8(ascii: "-"): .keyword
            case UInt8(ascii: "@"): .comment
            default: nil
            }
            if let kind { tokens.append(HighlightToken(start: start, end: end, kind: kind)) }
            return
        case .markup:
            tokenizeMarkup(bytes, from: start, to: end, state: &state, into: &tokens)
            return
        default:
            break
        }

        var i = start
        // Continue multi-line constructs.
        i = continueState(bytes, at: i, end: end, state: &state, into: &tokens)

        var firstNonSpace = true
        var previousSignificant: UInt8 = 0
        while i < end {
            let b = bytes[i]
            if Self.isSpace(b) { i += 1; continue }
            let atLineStart = firstNonSpace
            firstNonSpace = false

            // Line comments.
            if let comment = lineComments.first(where: { matches(bytes, i, end, $0) }) {
                // `#` inside shell words like `a#b` is not a comment, but at word start it is.
                _ = comment
                tokens.append(HighlightToken(start: i, end: end, kind: .comment))
                return
            }
            // Block comments.
            if let index = blockComments.firstIndex(where: { matches(bytes, i, end, $0.0) }) {
                let open = blockComments[index].0.count
                state = .blockComment(index)
                let tokenStart = i
                i += open
                i = scanBlockComment(bytes, at: i, end: end, state: &state, tokenStart: tokenStart, into: &tokens)
                continue
            }
            // Strings.
            if grammar.stringDelimiters.contains(b) {
                let triple = grammar.tripleQuotes && b != UInt8(ascii: "`") && i + 2 < end && bytes[i + 1] == b && bytes[i + 2] == b
                state = .string(b, triple: triple)
                let tokenStart = i
                i += triple ? 3 : 1
                i = scanString(bytes, at: i, end: end, state: &state, tokenStart: tokenStart, into: &tokens)
                if grammar.mode == .json, case .normal = state, let last = tokens.last, last.kind == .string {
                    // A string followed by `:` is a key.
                    var j = i
                    while j < end, Self.isSpace(bytes[j]) { j += 1 }
                    if j < end, bytes[j] == UInt8(ascii: ":") { tokens[tokens.count - 1].kind = .property }
                }
                previousSignificant = b
                continue
            }
            // Numbers.
            if Self.isDigit(b) || (b == UInt8(ascii: ".") && i + 1 < end && Self.isDigit(bytes[i + 1]) && !isIdentifier(previousSignificant)) {
                let tokenStart = i
                i += 1
                while i < end {
                    let c = bytes[i]
                    if Self.isAlpha(c) || Self.isDigit(c) || c == UInt8(ascii: ".") || c == UInt8(ascii: "_") {
                        i += 1
                    } else if (c == UInt8(ascii: "+") || c == UInt8(ascii: "-")), (bytes[i - 1] | 0x20) == UInt8(ascii: "e"),
                              !(bytes[tokenStart] == UInt8(ascii: "0") && i > tokenStart + 1 && (bytes[tokenStart + 1] | 0x20) == UInt8(ascii: "x")) {
                        i += 1
                    } else {
                        break
                    }
                }
                // `1.method()`: don't swallow a trailing dot.
                if bytes[i - 1] == UInt8(ascii: ".") { i -= 1 }
                tokens.append(HighlightToken(start: tokenStart, end: i, kind: .number))
                previousSignificant = UInt8(ascii: "0")
                continue
            }
            // Preprocessor directives.
            if grammar.preprocessor, atLineStart, b == UInt8(ascii: "#") {
                var j = i + 1
                while j < end, Self.isAlpha(bytes[j]) { j += 1 }
                tokens.append(HighlightToken(start: i, end: j, kind: .preprocessor))
                i = j
                continue
            }
            // Attributes: @name / #[attr].
            if let prefix = grammar.attributePrefix, b == prefix, i + 1 < end {
                if prefix == UInt8(ascii: "#"), bytes[i + 1] == UInt8(ascii: "[") || bytes[i + 1] == UInt8(ascii: "!") {
                    var j = i + 1
                    while j < end, bytes[j] != UInt8(ascii: "]") { j += 1 }
                    tokens.append(HighlightToken(start: i, end: min(j + 1, end), kind: .attribute))
                    i = min(j + 1, end)
                    continue
                }
                if Self.isAlpha(bytes[i + 1]) {
                    var j = i + 1
                    while j < end, isIdentifier(bytes[j]) { j += 1 }
                    let kind: CodeTokenKind = grammar.keywords.contains(word(bytes, i, j)) ? .keyword : .attribute
                    tokens.append(HighlightToken(start: i, end: j, kind: kind))
                    i = j
                    continue
                }
            }
            // Variables: $name, ${name}.
            if let prefix = grammar.variablePrefix, b == prefix, i + 1 < end {
                var j = i + 1
                if bytes[j] == UInt8(ascii: "{") {
                    while j < end, bytes[j] != UInt8(ascii: "}") { j += 1 }
                    j = min(j + 1, end)
                } else {
                    while j < end, isIdentifier(bytes[j]) || (j == i + 1 && (Self.isDigit(bytes[j]) || "@#?*!".utf8.contains(bytes[j]))) { j += 1 }
                }
                if j > i + 1 {
                    tokens.append(HighlightToken(start: i, end: j, kind: .variable))
                    i = j
                    continue
                }
            }
            // Identifiers.
            if Self.isAlpha(b) {
                let tokenStart = i
                while i < end, isIdentifier(bytes[i]) { i += 1 }
                if let kind = classify(bytes, tokenStart, i, end: end, previous: previousSignificant, atLineStart: atLineStart) {
                    tokens.append(HighlightToken(start: tokenStart, end: i, kind: kind))
                }
                previousSignificant = bytes[i - 1]
                continue
            }
            // Operators and punctuation.
            if Self.operatorBytes.contains(b) {
                let tokenStart = i
                while i < end, Self.operatorBytes.contains(bytes[i]) { i += 1 }
                tokens.append(HighlightToken(start: tokenStart, end: i, kind: .operator))
                previousSignificant = b
                continue
            }
            previousSignificant = b
            i += 1
        }
    }

    private func classify(_ bytes: UnsafeBufferPointer<UInt8>, _ start: Int, _ end: Int, end lineEnd: Int,
                          previous: UInt8, atLineStart: Bool) -> CodeTokenKind? {
        let text = word(bytes, start, end)
        let lookup = grammar.caseInsensitive ? text.lowercased() : text
        // Keys (`key:`) in YAML and CSS properties.
        if grammar.mode == .yaml || grammar.mode == .css {
            var j = end
            while j < lineEnd, Self.isSpace(bytes[j]) { j += 1 }
            if j < lineEnd, bytes[j] == UInt8(ascii: ":"), grammar.mode == .yaml || !atLineStart || true {
                if grammar.mode == .yaml || (j + 1 < lineEnd && bytes[j + 1] != UInt8(ascii: ":")) { return .property }
            }
        }
        if previous == UInt8(ascii: ".") { return grammar.mode == .css ? .type : .property }
        if grammar.keywords.contains(lookup) { return .keyword }
        if grammar.literals.contains(lookup) { return .literal }
        if grammar.types.contains(lookup) { return .type }
        if grammar.capitalizedTypes, Self.isUpper(bytes[start]) { return .type }
        // Function calls: identifier followed by `(`.
        var j = end
        while j < lineEnd, Self.isSpace(bytes[j]) { j += 1 }
        if j < lineEnd, bytes[j] == UInt8(ascii: "(") { return .function }
        if grammar.builtins.contains(lookup) { return .function }
        return nil
    }

    // MARK: Multi-line constructs

    private func continueState(_ bytes: UnsafeBufferPointer<UInt8>, at i: Int, end: Int,
                               state: inout LexState, into tokens: inout [HighlightToken]) -> Int {
        switch state {
        case .normal: return i
        case .blockComment: return scanBlockComment(bytes, at: i, end: end, state: &state, tokenStart: i, into: &tokens)
        case .string: return scanString(bytes, at: i, end: end, state: &state, tokenStart: i, into: &tokens)
        }
    }

    private func scanBlockComment(_ bytes: UnsafeBufferPointer<UInt8>, at start: Int, end: Int,
                                  state: inout LexState, tokenStart: Int, into tokens: inout [HighlightToken]) -> Int {
        guard case .blockComment(let index) = state else { return start }
        let close = blockComments[index].1
        var i = start
        while i < end {
            if matches(bytes, i, end, close) {
                i += close.count
                state = .normal
                tokens.append(HighlightToken(start: tokenStart, end: i, kind: .comment))
                return i
            }
            i += 1
        }
        if end > tokenStart { tokens.append(HighlightToken(start: tokenStart, end: end, kind: .comment)) }
        return end
    }

    private func scanString(_ bytes: UnsafeBufferPointer<UInt8>, at start: Int, end: Int,
                            state: inout LexState, tokenStart: Int, into tokens: inout [HighlightToken]) -> Int {
        guard case .string(let delimiter, let triple) = state else { return start }
        var i = start
        while i < end {
            let b = bytes[i]
            if b == Self.backslash, delimiter != UInt8(ascii: "`") || grammar.multilineBacktick {
                i += 2
                continue
            }
            if b == delimiter {
                if triple {
                    if i + 2 < end && bytes[i + 1] == delimiter && bytes[i + 2] == delimiter {
                        i += 3
                        state = .normal
                        tokens.append(HighlightToken(start: tokenStart, end: i, kind: .string))
                        return i
                    }
                } else {
                    i += 1
                    state = .normal
                    tokens.append(HighlightToken(start: tokenStart, end: i, kind: .string))
                    return i
                }
            }
            i += 1
        }
        let clampedEnd = min(i, end)
        if clampedEnd > tokenStart { tokens.append(HighlightToken(start: tokenStart, end: clampedEnd, kind: .string)) }
        // Single-line strings end with the line.
        let multiline = triple || (delimiter == UInt8(ascii: "`") && grammar.multilineBacktick)
        if !multiline { state = .normal }
        return end
    }

    // MARK: Markup

    private func tokenizeMarkup(_ bytes: UnsafeBufferPointer<UInt8>, from start: Int, to end: Int,
                                state: inout LexState, into tokens: inout [HighlightToken]) {
        var i = continueState(bytes, at: start, end: end, state: &state, into: &tokens)
        var inTag = false
        while i < end {
            let b = bytes[i]
            if !inTag {
                if let index = blockComments.firstIndex(where: { matches(bytes, i, end, $0.0) }) {
                    state = .blockComment(index)
                    let tokenStart = i
                    i = scanBlockComment(bytes, at: i + blockComments[index].0.count, end: end, state: &state, tokenStart: tokenStart, into: &tokens)
                    continue
                }
                if b == UInt8(ascii: "<"), i + 1 < end, Self.isAlpha(bytes[i + 1]) || bytes[i + 1] == UInt8(ascii: "/")
                    || bytes[i + 1] == UInt8(ascii: "?") || bytes[i + 1] == UInt8(ascii: "!") {
                    let tokenStart = i
                    i += 1
                    while i < end, isIdentifier(bytes[i]) || "/?!:-.".utf8.contains(bytes[i]) { i += 1 }
                    tokens.append(HighlightToken(start: tokenStart, end: i, kind: .tag))
                    inTag = true
                    continue
                }
                if b == UInt8(ascii: "&") {
                    var j = i + 1
                    while j < end, j - i < 10, bytes[j] != UInt8(ascii: ";"), !Self.isSpace(bytes[j]) { j += 1 }
                    if j < end, bytes[j] == UInt8(ascii: ";") {
                        tokens.append(HighlightToken(start: i, end: j + 1, kind: .literal))
                        i = j + 1
                        continue
                    }
                }
                i += 1
                continue
            }
            // Inside a tag.
            if b == UInt8(ascii: ">") || (b == UInt8(ascii: "/") && i + 1 < end && bytes[i + 1] == UInt8(ascii: ">")) {
                let tokenStart = i
                i += b == UInt8(ascii: ">") ? 1 : 2
                tokens.append(HighlightToken(start: tokenStart, end: i, kind: .tag))
                inTag = false
                continue
            }
            if b == UInt8(ascii: "\"") || b == UInt8(ascii: "'") {
                state = .string(b, triple: false)
                let tokenStart = i
                i = scanString(bytes, at: i + 1, end: end, state: &state, tokenStart: tokenStart, into: &tokens)
                continue
            }
            if Self.isAlpha(b) {
                let tokenStart = i
                while i < end, isIdentifier(bytes[i]) || bytes[i] == UInt8(ascii: "-") || bytes[i] == UInt8(ascii: ":") { i += 1 }
                tokens.append(HighlightToken(start: tokenStart, end: i, kind: .attribute))
                continue
            }
            i += 1
        }
    }
}
