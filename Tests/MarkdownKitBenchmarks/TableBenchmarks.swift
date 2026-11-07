import SwiftUI
import Testing
@testable import MarkdownKit

/// Table layout benchmarks: 30×30 tables measured and line-broken with CoreText.
@MainActor
@Suite(.serialized, .tags(.benchmark))
struct TableBenchmarks {
    let theme = ResolvedTheme(theme: .default, colorScheme: .light, dynamicTypeSize: .large)

    private func table(_ seed: UInt64) -> MarkdownTable {
        let blocks = MarkdownParser().parse(Fixtures.table(rows: 30, columns: 30, seed: seed)).blocks
        guard case .table(let table) = blocks.first else { fatalError("fixture is not a table") }
        return table
    }

    @Test func layoutSingle30x30Table() {
        let table = table(1)
        let engine = TableLayoutEngine(theme: theme, math: nil, textColor: theme.textColor)
        let result = Benchmark.measure("layout one 30×30 table", iterations: Benchmark.iterations(30)) {
            _ = engine.layout(table)
        }
        Benchmark.expect(result.median, lessThan: 15, "layout 30×30")
    }

    @Test func layoutTen30x30Tables() {
        let tables = (0..<10).map { table(UInt64($0 + 100)) }
        let preparer = MarkdownPreparer(theme: theme, math: nil)
        let blocks = tables.map(MarkdownBlock.table)
        let result = Benchmark.measure("prepare 10× 30×30 tables (cold)", iterations: Benchmark.iterations(10),
                                       setup: { PreparedBlockCache.shared.removeAll() }) {
            _ = preparer.prepare(blocks, key: 0)
        }
        Benchmark.expect(result.median, lessThan: 100, "prepare 10 tables")
    }

    @Test func layoutAtAccessibilitySize() {
        let large = ResolvedTheme(theme: .default, colorScheme: .light, dynamicTypeSize: .accessibility3)
        let table = table(2)
        let engine = TableLayoutEngine(theme: large, math: nil, textColor: large.textColor)
        let result = Benchmark.measure("layout 30×30 table at AX3", iterations: Benchmark.iterations(20)) {
            _ = engine.layout(table)
        }
        Benchmark.expect(result.median, lessThan: 20, "layout 30×30 AX3")
    }
}
