import SwiftUI
import Testing
@testable import MarkdownKit

@MainActor @Suite struct TableLayoutTests {
    let theme = ResolvedTheme(theme: .default, colorScheme: .light, dynamicTypeSize: .large)

    func layout(_ markdown: String) throws -> TableLayout {
        let document = MarkdownPipeline.prepare(MarkdownRequest(text: markdown, theme: theme, options: .default, isStreaming: false))
        guard case .table(let layout) = try #require(document.blocks.first?.content) else {
            Issue.record("expected table")
            throw CancellationError()
        }
        return layout
    }

    /// Light and dark layouts have the same geometry, so tile views must compare the identity, not offsets.
    @Test func identityChangesWithColorSchemeAndDynamicType() throws {
        let markdown = "| a | b |\n|---|---|\n| 1 | **2** |"
        func layout(_ theme: ResolvedTheme) throws -> TableLayout {
            let document = MarkdownPipeline.prepare(MarkdownRequest(text: markdown, theme: theme, options: .default, isStreaming: false))
            guard case .table(let layout) = try #require(document.blocks.first?.content) else { throw CancellationError() }
            return layout
        }
        let light = try layout(theme)
        let dark = try layout(ResolvedTheme(theme: .default, colorScheme: .dark, dynamicTypeSize: .large))
        let large = try layout(ResolvedTheme(theme: .default, colorScheme: .light, dynamicTypeSize: .accessibility2))
        #expect(light.columnOffsets == dark.columnOffsets && light.rowOffsets == dark.rowOffsets)
        #expect(light.identity != dark.identity)
        #expect(light.identity != large.identity)
        #expect(large.size.height > light.size.height)
        #expect(try layout(theme).identity == light.identity)
    }

    @Test func measuresColumnsAndRows() throws {
        let table = try layout("| a | b |\n|---|---:|\n| short | a much longer cell value here |\n| x | y |")
        #expect(table.columnCount == 2)
        #expect(table.rowCount == 3)
        let widths = (0..<2).map { table.columnOffsets[$0 + 1] - table.columnOffsets[$0] }
        #expect(widths[1] > widths[0])
        #expect(table.size.height > 0)
        #expect(table.plainRows[1] == ["short", "a much longer cell value here"])
    }

    @Test func wrapsLongCellsAtMaxColumnWidth() throws {
        let long = String(repeating: "word ", count: 80)
        let table = try layout("| h |\n|---|\n| \(long) |")
        let maxWidth = theme.length(theme.theme.table.maxColumnWidth, fontScale: theme.theme.table.font.scale)
            + 2 * theme.length(theme.theme.table.horizontalPadding, fontScale: theme.theme.table.font.scale)
        #expect(table.size.width <= ceil(maxWidth) + 1)
        #expect(table.cells[1][0].lines.count > 3)
    }

    @Test func collectsLinkRects() throws {
        let table = try layout("| h |\n|---|\n| [link](https://example.com) |")
        let link = try #require(table.links.first)
        #expect(link.url == URL(string: "https://example.com"))
        #expect(table.link(at: CGPoint(x: link.rect.midX, y: link.rect.midY)) == link.url)
    }

    @Test func handlesRaggedRows() throws {
        let table = try layout("| a | b | c |\n|---|---|---|\n| 1 |\n| 1 | 2 | 3 | 4 |")
        #expect(table.columnCount == 3)
        #expect(table.cells.allSatisfy { $0.count == 3 })
    }

    @Test func tilesCoverAllColumns() throws {
        let header = (0..<30).map { "Column \($0)" }.joined(separator: " | ")
        let delimiter = Array(repeating: "---", count: 30).joined(separator: "|")
        let row = (0..<30).map { "value \($0)" }.joined(separator: " | ")
        let table = try layout("| \(header) |\n|\(delimiter)|\n| \(row) |")
        let tiles = table.columnTiles(maxWidth: 512)
        #expect(tiles.first?.lowerBound == 0)
        #expect(tiles.last?.upperBound == 30)
        #expect(tiles.count > 1)
        #expect(zip(tiles, tiles.dropFirst()).allSatisfy { $0.upperBound == $1.lowerBound })
    }

    @Test func rendersTableView() throws {
        let renderer = ImageRenderer(content: MarkdownView("| a | b |\n|---|---|\n| 1 | **2** |").frame(width: 300))
        #expect(try #require(renderer.cgImage).height > 20)
    }
}
