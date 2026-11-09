import SwiftUI
import Testing
@testable import MarkdownKit

// Serialized: one test clears the shared cache that another one checks.
@MainActor @Suite(.serialized) struct StreamingTests {
    let theme = ResolvedTheme(theme: .default, colorScheme: .light, dynamicTypeSize: .large)

    /// A view showing a stale document (e.g. after a color scheme change) must update itself even when no
    /// view task runs, as for a long message whose last row is off screen in a lazy list.
    @Test func staleDocumentUpdatesWithoutAViewTask() async throws {
        let text = "# Title \(UUID().uuidString)\n\nSome **text**."
        let dark = ResolvedTheme(theme: .default, colorScheme: .dark, dynamicTypeSize: .large)
        let model = MarkdownViewModel()
        let lightRequest = MarkdownRequest(text: text, theme: theme, options: .default, isStreaming: false)
        let darkRequest = MarkdownRequest(text: text, theme: dark, options: .default, isStreaming: false)
        let first = try #require(model.document(for: lightRequest, synchronousLimit: .max))
        // Too large for synchronous preparation: the light document stays until the async one is ready.
        #expect(model.document(for: darkRequest, synchronousLimit: 0)?.key == first.key)
        var updated: PreparedDocument?
        for _ in 0..<300 {
            if let document = model.document(for: darkRequest, synchronousLimit: 0), document.key != first.key {
                updated = document
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(updated?.key == darkRequest.documentKey)
    }

    @Test func sessionReusesFrozenPreparedBlocks() {
        let session = StreamingSession()
        let base = "# Title\n\nFirst paragraph.\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\nStreaming tail"
        let first = session.update(MarkdownRequest(text: base, theme: theme, options: .default, isStreaming: true))
        let second = session.update(MarkdownRequest(text: base + " grows", theme: theme, options: .default, isStreaming: true))
        #expect(session.lastReusedBlocks >= 2)
        #expect(first.blocks.count == second.blocks.count)
        #expect(Array(first.blocks.dropLast()) == Array(second.blocks.dropLast()))
        #expect(first.blocks.last != second.blocks.last)
    }

    @Test func finalUpdateMatchesStaticRendering() {
        let text = Fixtures.sample
        let session = StreamingSession()
        var index = text.startIndex
        while index < text.endIndex {
            index = text.index(index, offsetBy: 7, limitedBy: text.endIndex) ?? text.endIndex
            _ = session.update(MarkdownRequest(text: String(text[..<index]), theme: theme, options: .default, isStreaming: true))
        }
        let final = session.update(MarkdownRequest(text: text, theme: theme, options: .default, isStreaming: false))
        MarkdownCache.shared.removeAll()
        let fresh = MarkdownPipeline.prepare(MarkdownRequest(text: text, theme: theme, options: .default, isStreaming: false))
        #expect(final.blocks.map(\.key) == fresh.blocks.map(\.key))
    }

    @Test func prefetchFillsCache() async {
        let texts = (0..<5).map { "Message \($0) with **bold** \(UUID().uuidString)" }
        await MarkdownPrefetcher.prefetch(texts)
        let resolved = ResolvedThemeCache.shared.theme(.default, colorScheme: .light, dynamicTypeSize: .large)
        for text in texts {
            #expect(MarkdownCache.shared[MarkdownRequest(text: text, theme: resolved, options: .default, isStreaming: false).cacheKey] != nil)
        }
    }

    @Test func streamingViewRenders() throws {
        let renderer = ImageRenderer(content: MarkdownView("Partial **answ", isStreaming: true).frame(width: 300))
        #expect(try #require(renderer.cgImage).height > 10)
        let blocks = ImageRenderer(content: VStack { MarkdownBlocks("# A\n\nB\n\n- c") }.frame(width: 300))
        #expect(try #require(blocks.cgImage).height > 40)
    }
}

enum Fixtures {
    static let sample = """
    # Streaming sample

    Paragraph with **bold**, `code`, a [link](https://example.com) and math $a^2+b^2=c^2$.

    | Name | Value |
    |------|------:|
    | one  | 1     |
    | two  | 2     |

    ```swift
    let answer = 42
    ```

    > Quote :rocket:

    1. First
    2. Second
    """
}
