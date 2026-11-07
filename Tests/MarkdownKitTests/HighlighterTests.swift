import Testing
@testable import MarkdownKit

@Suite struct HighlighterTests {
    func tokens(_ code: String, _ language: String, state: LexState = .normal) -> ([(String, CodeTokenKind)], LexState) {
        let grammar = try! #require(LanguageGrammar.lookup(language))
        var code = code
        code.makeContiguousUTF8()
        let bytes = Array(code.utf8)
        return bytes.withUnsafeBufferPointer { buffer in
            let (tokens, end) = SyntaxHighlighter(grammar: grammar).tokenize(buffer, state: state)
            return (tokens.map { (String(decoding: bytes[$0.start..<$0.end], as: UTF8.self), $0.kind) }, end)
        }
    }

    func kinds(_ code: String, _ language: String) -> [String: CodeTokenKind] {
        Dictionary(tokens(code, language).0.map { ($0.0, $0.1) }, uniquingKeysWith: { a, _ in a })
    }

    @Test func swiftTokens() {
        let k = kinds("@MainActor func load(_ x: Int) -> String { let s = \"hi\" // note\n return 0x1F }", "swift")
        #expect(k["@MainActor"] == .attribute)
        #expect(k["func"] == .keyword)
        #expect(k["load"] == .function)
        #expect(k["Int"] == .type)
        #expect(k["\"hi\""] == .string)
        #expect(k["// note"] == .comment)
        #expect(k["0x1F"] == .number)
    }

    @Test func multilineStateCarries() {
        let (first, state) = tokens("let a = 1 /* open", "swift")
        #expect(first.last?.1 == .comment)
        #expect(state == .blockComment(0))
        let (second, end) = tokens("still comment */ let b", "swift", state: state)
        #expect(second.first?.0 == "still comment */")
        #expect(second.first?.1 == .comment)
        #expect(end == .normal)

        let (_, tripleState) = tokens("s = \"\"\"start", "python")
        #expect(tripleState == .string(UInt8(ascii: "\""), triple: true))
    }

    @Test func pythonAndShellAndSQL() {
        #expect(kinds("def f(x):\n    return None  # c", "py")["None"] == .literal)
        #expect(kinds("echo $HOME ${PATH}", "bash")["$HOME"] == .variable)
        #expect(kinds("SELECT id FROM users WHERE x = 'a'", "sql")["SELECT"] == .keyword)
    }

    @Test func jsonKeysAndMarkup() {
        let json = kinds("{\"name\": \"value\", \"n\": 1, \"ok\": true}", "json")
        #expect(json["\"name\""] == .property)
        #expect(json["\"value\""] == .string)
        #expect(json["true"] == .literal)
        let html = kinds("<div class=\"a\">&amp;</div>", "html")
        #expect(html["<div"] == .tag)
        #expect(html["class"] == .attribute)
        #expect(html["&amp;"] == .literal)
    }

    @Test func diffLines() {
        let k = kinds("@@ -1 +1 @@\n-old\n+new", "diff")
        #expect(k["-old"] == .keyword)
        #expect(k["+new"] == .string)
    }

    @Test func unknownLanguageIsPlain() {
        #expect(LanguageGrammar.lookup("brainfuck") == nil)
        #expect(LanguageGrammar.lookup("TypeScript")?.name == "typescript")
    }

    @MainActor @Test func preparedCodeChunks() {
        let theme = ResolvedTheme(theme: .default, colorScheme: .dark, dynamicTypeSize: .large, textRenderer: .swiftUIText)
        let code = (0..<100).map { "let v\($0) = \($0)" }.joined(separator: "\n")
        let prepared = CodeHighlighting(theme: theme).prepare(MarkdownCodeBlock(language: "swift", code: code))
        #expect(prepared.chunks.count == 3)
        #expect(prepared.lineCount == 100)
        let joined = prepared.chunks.map { String($0.text!.characters) }.joined()
        #expect(joined == code)
        #expect(prepared.chunks[0].text!.runs.count > 10)

        let coreTextTheme = ResolvedTheme(theme: .default, colorScheme: .dark, dynamicTypeSize: .large, textRenderer: .coreText)
        let typeset = CodeHighlighting(theme: coreTextTheme).prepare(MarkdownCodeBlock(language: "swift", code: code))
        #expect(typeset.usesCoreText)
        #expect(typeset.chunks.reduce(0) { $0 + ($1.lines?.lines.count ?? 0) } == 100)
        #expect(typeset.contentWidth > 50 && typeset.lineHeight > 10)
    }
}
