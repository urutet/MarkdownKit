import SwiftUI
import Testing
@testable import MarkdownKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// SwiftUI layout cost on the main thread for prepared (cached) documents.
@MainActor
@Suite(.serialized, .tags(.benchmark))
struct RenderBenchmarks {
    static let width: CGFloat = 390

    /// Hosts `view` and runs a full layout pass, returning its height.
    @discardableResult
    static func layout<V: View>(_ view: V) -> CGFloat {
        #if canImport(UIKit)
        let controller = UIHostingController(rootView: view.frame(width: width))
        return controller.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
        #else
        let host = NSHostingView(rootView: view.frame(width: width))
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
        #endif
    }

    /// Prepares `text` like the prefetcher would, optionally with the display width (text typeset off-main).
    @MainActor
    private func warm(_ text: String, width: CGFloat? = nil) {
        let theme = ResolvedThemeCache.shared.theme(.default, colorScheme: .light, dynamicTypeSize: .large)
        _ = MarkdownPipeline.prepare(MarkdownRequest(text: text, theme: theme, options: .default, isStreaming: false,
                                                     layoutWidth: width))
    }

    nonisolated static func messages(seed: UInt64) -> [String] {
        (0..<40).map { Fixtures.chatMessage(bytes: 2_000 + ($0 % 5) * 1_500, seed: UInt64($0) + seed, includeTables: $0 % 4 == 0) }
    }

    @Test func firstLayoutOfChatMessagesPrefetchedAtWidth() {
        MarkdownCache.shared.removeAll()
        let messages = Self.messages(seed: 1_000)
        messages.forEach { warm($0, width: Self.width) }
        var index = 0
        let result = Benchmark.measure("first layout of a chat message (2–8KB), prefetched at width",
                                       iterations: messages.count) {
            Self.layout(MarkdownView(messages[index % messages.count]))
            index += 1
        }
        // A whole message appearing at once (MarkdownView in a lazy list) should fit in one 60 Hz frame.
        Benchmark.expect(result.median, lessThan: 16, "message first layout median (prefetched)")
    }

    @Test func firstLayoutOfChatMessages() {
        MarkdownCache.shared.removeAll()
        let messages = Self.messages(seed: 0)
        messages.forEach { warm($0) }
        var index = 0
        let result = Benchmark.measure("first layout of a chat message (2–8KB), parsed but not typeset",
                                       iterations: messages.count) {
            Self.layout(MarkdownView(messages[index % messages.count]))
            index += 1
        }
        Benchmark.expect(result.median, lessThan: 16, "message first layout median")
    }

    @Test func blockByBlockLayoutForLazyStacks() {
        // With MarkdownBlocks in a LazyVStack, each block is a separate row: measure per-block cost.
        MarkdownCache.shared.removeAll()
        let text = Fixtures.chatMessage(bytes: 8_000, seed: 77)
        warm(text, width: Self.width)
        let theme = ResolvedThemeCache.shared.theme(.default, colorScheme: .light, dynamicTypeSize: .large)
        let document = MarkdownPipeline.prepare(MarkdownRequest(text: text, theme: theme, options: .default, isStreaming: false))
        var index = 0
        let result = Benchmark.measure("layout of one block (8KB message, \(document.blocks.count) blocks)",
                                       iterations: document.blocks.count * 3) {
            let block = document.blocks[index % document.blocks.count]
            Self.layout(BlockView(block: block, theme: theme, isFirst: false))
            index += 1
        }
        // MarkdownBlocks rows should fit comfortably in a 120 Hz frame (8.3 ms).
        Benchmark.expect(result.p95, lessThan: 4, "per-block layout p95")
    }

    @Test func firstLayoutOfTableHeavyDocument() {
        let text = Fixtures.tableHeavyDocument(tableCount: 10, rows: 30, columns: 30)
        warm(text)
        let result = Benchmark.measure("first layout of 10× 30×30 tables doc (cached)", iterations: Benchmark.iterations(10)) {
            Self.layout(MarkdownView(text))
        }
        Benchmark.expect(result.median, lessThan: 33, "table-heavy first layout")
    }

    @Test func canvasTableVersusGridOfText() {
        let markdown = Fixtures.table(rows: 30, columns: 30, seed: 5)
        warm(markdown)
        let canvas = Benchmark.measure("30×30 table: MarkdownKit Canvas tiles", iterations: Benchmark.iterations(10)) {
            Self.layout(MarkdownView(markdown))
        }
        let rows = markdown.split(separator: "\n").enumerated().filter { $0.offset != 1 }.map { line in
            line.element.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        let grid = Benchmark.measure("30×30 table: SwiftUI Grid of Text (baseline)", iterations: Benchmark.iterations(5)) {
            Self.layout(ScrollView(.horizontal) {
                Grid(alignment: .leading) {
                    ForEach(rows.indices, id: \.self) { r in
                        GridRow {
                            ForEach(rows[r].indices, id: \.self) { c in
                                Text(LocalizedStringKey(rows[r][c])).frame(maxWidth: 220, alignment: .leading)
                            }
                        }
                    }
                }
            })
        }
        print(String(format: "  Canvas is %.1f× faster than Grid", grid.median / max(canvas.median, 0.001)))
        Benchmark.expect(canvas.median, lessThan: grid.median, "Canvas table vs Grid baseline")
    }

    @Test func relayoutWhileStreaming() {
        // Re-layout after the last block changes: unchanged blocks are skipped by Equatable diffing.
        let text = Fixtures.chatMessage(bytes: 20_000, seed: 21)
        let theme = ResolvedThemeCache.shared.theme(.default, colorScheme: .light, dynamicTypeSize: .large)
        let session = StreamingSession()
        let model = StreamingHostModel()
        #if canImport(UIKit)
        let host = UIHostingController(rootView: StreamingHost(model: model).frame(width: Self.width))
        #else
        let host = NSHostingView(rootView: StreamingHost(model: model).frame(width: Self.width))
        #endif
        var samples: [Duration] = []
        let clock = ContinuousClock()
        var count = text.count / 2
        while count < text.count {
            count = min(text.count, count + 40)
            let request = MarkdownRequest(text: String(text.prefix(count)), theme: theme, options: .default, isStreaming: true)
            let document = session.update(request)
            let start = clock.now
            model.document = document
            model.theme = theme
            #if canImport(UIKit)
            _ = host.sizeThatFits(in: CGSize(width: Self.width, height: .greatestFiniteMagnitude))
            #else
            host.layoutSubtreeIfNeeded()
            _ = host.fittingSize
            #endif
            samples.append(clock.now - start)
        }
        let result = Benchmark.record("streaming re-layout of a 20KB message (main thread)", samples: samples)
        Benchmark.expect(result.p95, lessThan: 8, "streaming re-layout p95")
    }
}

@MainActor @Observable
final class StreamingHostModel {
    var document = PreparedDocument.empty
    var theme: ResolvedTheme?
}

struct StreamingHost: View {
    let model: StreamingHostModel
    var body: some View {
        if let theme = model.theme {
            MarkdownDocumentView(document: model.document, theme: theme, showsCursor: true)
        }
    }
}
