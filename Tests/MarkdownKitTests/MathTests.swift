import SwiftUI
import Testing
@testable import MarkdownKit

@MainActor @Suite struct MathTests {
    let theme = ResolvedTheme(theme: .default, colorScheme: .light, dynamicTypeSize: .large, textRenderer: .coreText)

    @Test func rendersInlineAndDisplay() throws {
        let renderer = SwiftMathRenderer()
        let inline = try #require(renderer.render(latex: "x^2 + y_1", display: false, fontSize: 17, color: theme.textColor, font: .latinModern))
        let display = try #require(renderer.render(latex: "\\frac{a}{b}", display: true, fontSize: 17, color: theme.textColor, font: .latinModern))
        #expect(inline.image.scale >= 3)
        #expect(inline.image.size.height > 8 && inline.image.size.height < 40)
        #expect(inline.descent >= 0 && inline.descent < inline.image.size.height)
        #expect(display.image.size.height > inline.image.size.height)
    }

    @Test func invalidLatexFallsBack() {
        let renderer = SwiftMathRenderer()
        #expect(renderer.render(latex: "\\frac{", display: false, fontSize: 17, color: theme.textColor, font: .latinModern) == nil)
    }

    @Test func cachesResults() throws {
        let renderer = SwiftMathRenderer()
        let a = try #require(renderer.render(latex: "a+b", display: false, fontSize: 17, color: theme.textColor, font: .xits))
        let b = try #require(renderer.render(latex: "a+b", display: false, fontSize: 17, color: theme.textColor, font: .xits))
        #expect(a.image == b.image)
    }

    @Test func preparesMathSegmentsAndBlocks() throws {
        let document = MarkdownPipeline.prepare(MarkdownRequest(text: "Energy $E = mc^2$ here.\n\n$$\\int_0^1 x\\,dx$$",
                                                                theme: theme, options: .default, isStreaming: false))
        guard case .text(let text, _) = try #require(document.blocks.first?.content) else { Issue.record("no text"); return }
        let math = try #require(text.rich).attachments.compactMap { if case .image(let image, _) = $0.content { return image }; return nil }
        #expect(math.count == 1)
        guard case .math(let block) = document.blocks[1].content else { Issue.record("no math block"); return }
        #expect(block.isDisplay && block.image != nil)
    }

    @Test func mathInTableCells() throws {
        let document = MarkdownPipeline.prepare(MarkdownRequest(text: "| f | v |\n|---|---|\n| $x^2$ | 1 |",
                                                                theme: theme, options: .default, isStreaming: false))
        guard case .table(let layout) = try #require(document.blocks.first?.content) else { Issue.record("no table"); return }
        #expect(layout.cells[1][0].attachments.count == 1)
    }
}
