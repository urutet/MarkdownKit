import SwiftUI
import Testing
@testable import MarkdownKit

@MainActor
@Suite(.serialized, .tags(.benchmark))
struct HighlightingBenchmarks {
    let theme = ResolvedTheme(theme: .default, colorScheme: .light, dynamicTypeSize: .large)
    nonisolated static let source = Fixtures.swiftSource(lines: 5_000)

    @Test func tokenize5000Lines() {
        var code = Self.source
        code.makeContiguousUTF8()
        let highlighter = SyntaxHighlighter(grammar: .swift)
        let result = Benchmark.measure("tokenize 5000-line Swift", iterations: Benchmark.iterations(20)) {
            _ = code.utf8.withContiguousStorageIfAvailable { highlighter.tokenize($0, state: .normal) }
        }
        Benchmark.expect(result.median, lessThan: 25, "tokenize 5000 lines")
    }

    @Test func highlight5000LinesCold() {
        let block = MarkdownCodeBlock(language: "swift", code: Self.source)
        var salt = 0
        let result = Benchmark.measure("highlight 5000-line Swift into chunks (cold)", iterations: Benchmark.iterations(10)) {
            // Vary the theme fingerprint so the chunk cache misses.
            salt += 1
            var markdownTheme = MarkdownTheme.default
            markdownTheme.text.lineSpacing = .pt(CGFloat(salt) / 1000)
            let theme = ResolvedThemeCache.shared.theme(markdownTheme, colorScheme: .light, dynamicTypeSize: .large)
            _ = CodeHighlighting(theme: theme).prepare(block)
        }
        Benchmark.expect(result.median, lessThan: 120, "highlight 5000 lines")
    }

    @Test func streamingCodeBlockReusesChunks() {
        let lines = Self.source.split(separator: "\n").prefix(400)
        let highlighting = CodeHighlighting(theme: theme)
        var samples: [Duration] = []
        let clock = ContinuousClock()
        for count in stride(from: 10, through: lines.count, by: 3) {
            let block = MarkdownCodeBlock(language: "swift", code: lines.prefix(count).joined(separator: "\n"), isClosed: false)
            let start = clock.now
            _ = highlighting.prepare(block)
            samples.append(clock.now - start)
        }
        let result = Benchmark.record("streaming 400-line code block (per update)", samples: samples)
        Benchmark.expect(result.p99, lessThan: 4, "streaming code update p99")
    }
}
