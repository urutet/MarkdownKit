import Testing
@testable import MarkdownKit

@Suite struct ModelTests {
    @Test func tableColumnCountUsesWidestRow() {
        let table = MarkdownTable(
            alignments: [.left, .right],
            header: [[.text("a")], [.text("b")]],
            rows: [[[.text("1")], [.text("2")], [.text("3")]]]
        )
        #expect(table.columnCount == 3)
    }

    @Test func plainTextFlattensInlines() {
        let inlines: [MarkdownInline] = [.text("Hi "), .strong([.text("there")]), .softBreak, .code("x")]
        #expect(inlines.plainText == "Hi there x")
    }
}
