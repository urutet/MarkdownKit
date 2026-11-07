import SwiftUI
import Testing
@testable import MarkdownKit

/// Parse and prepare benchmarks on large documents and 30×30 tables.
@MainActor
@Suite(.serialized, .tags(.benchmark))
struct ParsingBenchmarks {
    nonisolated static let sizes = [10_000, 100_000, 1_000_000]
    nonisolated static let tableHeavy = Fixtures.tableHeavyDocument(tableCount: 10, rows: 30, columns: 30)
    let theme = ResolvedTheme(theme: .default, colorScheme: .light, dynamicTypeSize: .large)

    @Test(arguments: MarkdownParserKind.allCases, sizes)
    func parseChatMessage(parser kind: MarkdownParserKind, bytes: Int) {
        let text = Fixtures.chatMessage(bytes: bytes)
        let parser = kind.make()
        let result = Benchmark.measure("parse \(kind) chat \(bytes / 1000)KB", iterations: Benchmark.iterations(bytes > 500_000 ? 5 : 20)) {
            _ = parser.parse(text)
        }
        // Linear-ish budget: ~25 ms per 100 KB.
        Benchmark.expect(result.median, lessThan: max(5, Double(bytes) / 100_000 * 25), "parse \(bytes / 1000)KB")
    }

    @Test(arguments: MarkdownParserKind.allCases)
    func parseTableHeavyDocument(parser kind: MarkdownParserKind) {
        let parser = kind.make()
        print("table-heavy document: \(Self.tableHeavy.utf8.count / 1000) KB, 10 tables of 30×30")
        let result = Benchmark.measure("parse \(kind) 10× 30×30 tables", iterations: Benchmark.iterations(20)) {
            _ = parser.parse(Self.tableHeavy)
        }
        Benchmark.expect(result.median, lessThan: 60, "parse table-heavy")
    }

    @Test func prepareTableHeavyColdCache() {
        let request = MarkdownRequest(text: Self.tableHeavy, theme: theme, options: .default, isStreaming: false)
        let result = Benchmark.measure("parse+prepare 10× 30×30 tables (cold)", iterations: Benchmark.iterations(10),
                                       setup: { MarkdownCache.shared.removeAll() }) {
            _ = MarkdownPipeline.prepare(request)
        }
        Benchmark.expect(result.median, lessThan: 150, "parse+prepare table-heavy")
    }

    @Test(arguments: [10_000, 100_000])
    func prepareChatMessageColdCache(bytes: Int) {
        let request = MarkdownRequest(text: Fixtures.chatMessage(bytes: bytes), theme: theme, options: .default, isStreaming: false)
        let result = Benchmark.measure("parse+prepare chat \(bytes / 1000)KB (cold)", iterations: Benchmark.iterations(10),
                                       setup: { MarkdownCache.shared.removeAll() }) {
            _ = MarkdownPipeline.prepare(request)
        }
        Benchmark.expect(result.median, lessThan: max(8, Double(bytes) / 100_000 * 80), "parse+prepare \(bytes / 1000)KB")
    }

    @Test func cacheHit() {
        let request = MarkdownRequest(text: Self.tableHeavy, theme: theme, options: .default, isStreaming: false)
        _ = MarkdownPipeline.prepare(request)
        let result = Benchmark.measure("cache hit (table-heavy key)", iterations: 200) {
            _ = MarkdownCache.shared[request.cacheKey]
        }
        Benchmark.expect(result.median, lessThan: 0.5, "cache hit")
    }
}
