import SwiftUI
import Testing
@testable import MarkdownKit

@MainActor @Suite struct ThemeTests {
    @Test func lengthsAreFontRelative() {
        #expect(MarkdownLength.em(2).resolve(fontSize: 10) == 20)
        #expect(MarkdownLength.pt(3).resolve(fontSize: 10) == 3)
    }

    @Test func baseSizeFollowsDynamicType() {
        var theme = MarkdownTheme()
        theme.text.baseSize = 17
        let large = ResolvedTheme(theme: theme, colorScheme: .light, dynamicTypeSize: .large)
        let huge = ResolvedTheme(theme: theme, colorScheme: .light, dynamicTypeSize: .accessibility3)
        #expect(large.baseSize == 17)
        #expect(huge.baseSize == 40)
        #expect(huge.length(.em(1)) > large.length(.em(1)))
        #expect(large != huge)
    }

    @Test func fingerprintChangesWithColorScheme() {
        let light = ResolvedTheme(theme: .default, colorScheme: .light, dynamicTypeSize: .large)
        let dark = ResolvedTheme(theme: .default, colorScheme: .dark, dynamicTypeSize: .large)
        #expect(light.fingerprint != dark.fingerprint)
        #expect(light.codeColors[Int(CodeTokenKind.keyword.rawValue)] != dark.codeColors[Int(CodeTokenKind.keyword.rawValue)])
    }
}

@MainActor @Suite struct PreparationTests {
    let theme = ResolvedTheme(theme: .default, colorScheme: .light, dynamicTypeSize: .large, textRenderer: .coreText)

    func prepare(_ text: String) -> PreparedDocument {
        MarkdownPipeline.prepare(MarkdownRequest(text: text, theme: theme, options: .default, isStreaming: false))
    }

    @Test func preparesBlockKinds() {
        let document = prepare("# H\n\npara [link](https://a.b)\n\n> quote\n\n- [x] a\n- b\n\n---\n\n![alt](https://a.b/i.png)")
        let kinds = document.blocks.map { block -> String in
            switch block.content {
            case .text(_, .heading(let l)): "h\(l)"
            case .text: "text"
            case .blockquote: "quote"
            case .list: "list"
            case .thematicBreak: "rule"
            case .image: "image"
            default: "other"
            }
        }
        #expect(kinds == ["h1", "text", "quote", "list", "rule", "image"])
    }

    @Test func richTextLinksAndLayout() throws {
        let document = prepare("see [docs](https://example.com/x) and more words to wrap across several lines of text here")
        guard case .text(let text, _) = try #require(document.blocks.first?.content) else { Issue.record("expected text"); return }
        let rich = try #require(text.rich)
        #expect(rich.links == [URL(string: "https://example.com/x")!])
        let narrow = rich.layout(width: 120)
        let wide = rich.layout(width: 2000)
        #expect(narrow.lines.count > wide.lines.count)
        #expect(narrow.size.height > wide.size.height)
        let link = try #require(narrow.links.first)
        #expect(narrow.link(at: CGPoint(x: link.rect.midX, y: link.rect.midY)) == link.url)
        #expect(rich.naturalLayout().lines.count == 1)
    }

    @Test func prelayoutAtKnownWidth() throws {
        let request = MarkdownRequest(text: "- item with some text \(UUID())\n\n> quoted \(UUID())", theme: theme, options: .default,
                                      isStreaming: false, layoutWidth: 300)
        let document = MarkdownPipeline.prepare(request)
        guard case .list(let list) = try #require(document.blocks.first?.content),
              case .text(let item, _) = try #require(list.items.first?.blocks.first?.content) else { Issue.record("no list"); return }
        let expected = 300 - list.markerWidth - list.markerSpacing
        #expect(abs((item.rich?.lastLayout?.size.width ?? 0) - expected) < 0.01)
    }

    @Test func linkRunsCarryURL() throws {
        let swiftUITheme = ResolvedTheme(theme: .default, colorScheme: .light, dynamicTypeSize: .large, textRenderer: .swiftUIText)
        let document = MarkdownPipeline.prepare(MarkdownRequest(text: "see [docs](https://example.com/x)", theme: swiftUITheme,
                                                                options: .default, isStreaming: false))
        guard case .text(let text, _) = try #require(document.blocks.first?.content),
              case .text(let attributed) = try #require(text.segments.first) else {
            Issue.record("expected text"); return
        }
        let links = attributed.runs.compactMap(\.link)
        #expect(links == [URL(string: "https://example.com/x")!])
        #expect(text.plainText == "see docs")
    }

    @Test func blockKeysAreStableAndCached() {
        let a = prepare("one\n\ntwo")
        let b = prepare("one\n\ntwo\n\nthree")
        #expect(a.blocks[0].key == b.blocks[0].key)
        #expect(a.blocks[1].key == b.blocks[1].key)
        #expect(MarkdownCache.shared[MarkdownRequest(text: "one\n\ntwo", theme: theme, options: .default, isStreaming: false).cacheKey] != nil)
    }

    @Test func listMarkers() throws {
        let document = prepare("9. a\n10. b")
        guard case .list(let list) = try #require(document.blocks.first?.content) else { Issue.record("no list"); return }
        guard case .text(let marker) = list.items[1].marker else { Issue.record("no marker"); return }
        #expect(String(marker.characters) == "10.")
    }

    @MainActor @Test func viewRendersWithoutCrashing() throws {
        let view = MarkdownView("# Title\n\nHello **world** with `code` and a [link](https://x.y).\n\n- a\n- b\n\n> quote")
            .frame(width: 320)
        let renderer = ImageRenderer(content: view)
        let image = try #require(renderer.cgImage)
        #expect(image.height > 50)
    }

    @Test func swiftUITextIsTheDefaultRendererAndTextIsSelectable() {
        let environment = EnvironmentValues()
        #expect(environment.markdownTextRenderer == .swiftUIText)
        #expect(MarkdownTextRenderer.default == .swiftUIText)
        #expect(environment.markdownTextSelection)
    }
}
