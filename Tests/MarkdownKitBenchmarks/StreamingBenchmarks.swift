import SwiftUI
import Testing
@testable import MarkdownKit

/// Streaming: replays documents in small chunks, measuring each incremental parse + prepare.
@MainActor
@Suite(.serialized, .tags(.benchmark))
struct StreamingBenchmarks {
    let theme = ResolvedTheme(theme: .default, colorScheme: .light, dynamicTypeSize: .large, textRenderer: .coreText)

    private func replay(_ text: String, chunk: Int, label: String) -> BenchmarkResult {
        MarkdownCache.shared.removeAll()
        let session = StreamingSession()
        let clock = ContinuousClock()
        var samples: [Duration] = []
        var index = text.startIndex
        while index < text.endIndex {
            index = text.index(index, offsetBy: chunk, limitedBy: text.endIndex) ?? text.endIndex
            let request = MarkdownRequest(text: String(text[..<index]), theme: theme, options: .default, isStreaming: index < text.endIndex)
            let start = clock.now
            _ = session.update(request)
            samples.append(clock.now - start)
        }
        let result = Benchmark.record(label, samples: samples)
        print(String(format: "  total %.1f ms for %d updates", result.total, samples.count))
        return result
    }

    @Test func streamChatMessage() {
        let text = Fixtures.chatMessage(bytes: 30_000, seed: 11)
        let result = replay(text, chunk: 4, label: "stream 30KB chat, 4 chars/update")
        Benchmark.expect(result.median, lessThan: 1.5, "streaming update median")
        Benchmark.expect(result.p99, lessThan: 4, "streaming update p99")
    }

    @Test func streamLongMessageCostStaysFlat() {
        // Per-update cost must not grow with message length: compare updates near the start and the end.
        let text = Fixtures.chatMessage(bytes: 100_000, seed: 12, includeTables: false)
        let result = replay(text, chunk: 24, label: "stream 100KB chat, 24 chars/update")
        let samples = result.samples.map(\.milliseconds)
        let early = samples.prefix(samples.count / 10).sorted()[samples.count / 20]
        let late = samples.suffix(samples.count / 10).sorted()[samples.count / 20]
        print(String(format: "  early median %.3f ms, late median %.3f ms", early, late))
        Benchmark.expect(late, lessThan: max(early * 3, 1), "late updates vs early updates")
    }

    @Test func streamTablesOf30x30() {
        let text = Fixtures.tableHeavyDocument(tableCount: 3, rows: 30, columns: 30)
        let result = replay(text, chunk: 16, label: "stream 3× 30×30 tables, 16 chars/update")
        // Off the main thread; a growing 30×30 table re-parses its block each update.
        Benchmark.expect(result.p99, lessThan: 16, "streaming table update p99 (one frame)")
    }
}
