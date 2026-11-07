import Testing
@testable import MarkdownKit

@Suite struct ParserTests {
    let parser = MarkdownParser()

    @Test func headingsAndParagraphs() {
        let doc = parser.parseDocument("# Title\n\nHello **bold** and *it* ~~gone~~ `code`.")
        #expect(doc.blocks == [
            .heading(level: 1, [.text("Title")]),
            .paragraph([.text("Hello "), .strong([.text("bold")]), .text(" and "), .emphasis([.text("it")]),
                        .text(" "), .strikethrough([.text("gone")]), .text(" "), .code("code"), .text(".")]),
        ])
    }

    @Test func gfmTable() throws {
        let doc = parser.parseDocument("| a | b |\n|:--|--:|\n| 1 | [x](https://x.com) |\n")
        guard case .table(let table) = try #require(doc.blocks.first) else { Issue.record("not a table"); return }
        #expect(table.alignments == [.left, .right])
        #expect(table.header == [[.text("a")], [.text("b")]])
        #expect(table.rows.count == 1)
        #expect(table.rows[0][1] == [.link(destination: "https://x.com", [.text("x")])])
    }

    @Test func taskListAndTightness() throws {
        let doc = parser.parseDocument("- [x] done\n- [ ] todo\n- plain\n")
        guard case .list(let list) = try #require(doc.blocks.first) else { Issue.record("not a list"); return }
        #expect(list.items.map(\.checkbox) == [true, false, nil])
        #expect(list.isTight)
        #expect(!list.isOrdered)

        let loose = parser.parseDocument("3. a\n\n4. b\n")
        guard case .list(let ordered) = try #require(loose.blocks.first) else { Issue.record("not a list"); return }
        #expect(ordered.isOrdered && ordered.startIndex == 3 && !ordered.isTight)
    }

    @Test func fencedCode() throws {
        let doc = parser.parseDocument("```swift\nlet x = 1\n```\n")
        #expect(doc.blocks == [.codeBlock(MarkdownCodeBlock(language: "swift", code: "let x = 1", isClosed: true))])
        let open = parser.parseDocument("```python\nprint(1)")
        #expect(open.blocks == [.codeBlock(MarkdownCodeBlock(language: "python", code: "print(1)", isClosed: false))])
    }

    @Test func inlineAndDisplayMath() {
        let doc = parser.parseDocument("Euler: $e^{i\\pi} + 1 = 0$ where $a_1 * b_2$.\n\n$$\n\\int_0^1 x\\,dx\n$$\n")
        #expect(doc.blocks == [
            .paragraph([.text("Euler: "), .math("e^{i\\pi} + 1 = 0"), .text(" where "), .math("a_1 * b_2"), .text(".")]),
            .mathBlock("\\int_0^1 x\\,dx"),
        ])
    }

    @Test func latexDelimitersAndCurrency() {
        let doc = parser.parseDocument("Cost $5 and $10. Area \\(r^2\\).\n\\[x = 1\\]")
        #expect(doc.blocks == [
            .paragraph([.text("Cost $5 and $10. Area "), .math("r^2"), .text(".")]),
            .mathBlock("x = 1"),
        ])
    }

    @Test func mathIsNotExtractedFromCode() {
        let doc = parser.parseDocument("`$x$` and\n```\n$y$\n```")
        #expect(doc.blocks == [
            .paragraph([.code("$x$"), .text(" and")]),
            .codeBlock(MarkdownCodeBlock(language: nil, code: "$y$", isClosed: true)),
        ])
    }

    @Test func emojiShortcodes() {
        let doc = parser.parseDocument("Hi :party_parrot: at 10:30:00")
        #expect(doc.blocks == [.paragraph([.text("Hi "), .emoji("party_parrot"), .text(" at 10:30:00")])])
    }

    @Test func imagesAndBreaks() {
        let doc = parser.parseDocument("![alt text](https://a.com/i.png \"t\")\nline<br>next")
        #expect(doc.blocks == [.paragraph([
            .image(source: "https://a.com/i.png", alt: "alt text", title: "t"),
            .softBreak, .text("line"), .lineBreak, .text("next"),
        ])])
    }

    @Test func lastBlockStartIsSourceOffset() {
        let source = "$$x$$ intro\n\n# Head\n\nlast para"
        let result = parser.parse(source)
        let offset = try! #require(result.lastBlockStart)
        #expect(String(source.utf8.dropFirst(offset))! == "last para")
    }
}

@Suite struct IncrementalParserTests {
    @Test func streamingMatchesFullParse() {
        let text = """
        # Streaming

        Some paragraph with **bold** and a [link](https://example.com).

        | a | b |
        |---|---|
        | 1 | 2 |
        | 3 | 4 |

        ```swift
        let x = 1
        ```

        - one
        - two

        Final $x^2$ words.
        """
        let incremental = IncrementalParser()
        var index = text.startIndex
        while index < text.endIndex {
            index = text.index(index, offsetBy: 3, limitedBy: text.endIndex) ?? text.endIndex
            _ = incremental.update(String(text[..<index]), isStreaming: true)
        }
        let final = incremental.update(text, isStreaming: false)
        #expect(final == MarkdownParser().parseDocument(text).blocks)
        #expect(incremental.reparsedBytes < text.utf8.count / 2)
    }

    @Test func nonPrefixUpdateReparsesFully() {
        let incremental = IncrementalParser()
        _ = incremental.update("# A\n\nfirst\n\nsecond", isStreaming: false)
        let blocks = incremental.update("# B\n\nother", isStreaming: false)
        #expect(blocks == [.heading(level: 2 - 1, [.text("B")]), .paragraph([.text("other")])])
    }

    @Test func repairsDanglingMarkers() {
        let incremental = IncrementalParser()
        #expect(incremental.update("Hello **wor", isStreaming: true) == [.paragraph([.text("Hello "), .strong([.text("wor")])])])
        #expect(incremental.update("Use `code", isStreaming: true) == [.paragraph([.text("Use "), .code("code")])])
    }

    @Test func hidesPartialTableRows() throws {
        let incremental = IncrementalParser()
        #expect(incremental.update("Intro\n\n| a | b |\n", isStreaming: true) == [.paragraph([.text("Intro")])])
        let blocks = incremental.update("Intro\n\n| a | b |\n|---|---|\n| 1 | 2 |\n| 3", isStreaming: true)
        guard case .table(let table) = try #require(blocks.last) else { Issue.record("expected table"); return }
        #expect(table.rows.count == 1)
    }
}
