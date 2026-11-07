import SwiftUI
import Testing
@testable import MarkdownKit

/// Renders sample documents to PNG files when `MARKDOWNKIT_SNAPSHOT_DIR` is set (for visual review).
@MainActor @Suite struct SnapshotRenderer {
    static let samples: [(String, String)] = [
        ("table", "Intro paragraph with a [link](https://example.com).\n\n| Name | Value | Notes |\n|:--|--:|:-:|\n| **alpha** | 1.25 | `code` here |\n| beta ~~old~~ | 22.5 | a much longer cell value that should wrap onto multiple lines because it is long |\n| gamma 🚀 | 3 | [docs](https://x.y) |\n\nAfter table."),
        ("code", "Some code:\n\n```swift\n@MainActor\nfinal class Model: ObservableObject {\n    @Published var items: [String] = [\"a\", \"b\"] // comment\n    func load(id: Int) async throws -> Int {\n        return id * 0x2A\n    }\n}\n```\n\n```python\ndef fib(n):\n    \"\"\"Docstring\"\"\"\n    return n if n < 2 else fib(n - 1) + fib(n - 2)  # recursion\n```"),
        ("text", "# Heading 1\n## Heading 2\nA paragraph with **bold**, *italic*, `inline code`, ~~strike~~ and a [link](https://example.com).\n\n> A blockquote with *emphasis*\n> spanning lines.\n\n- Bullet one\n- Bullet two\n  - Nested\n- [x] Done task\n- [ ] Open task\n\n1. First\n2. Second\n\n---\n\nThe end."),
    ]

    @Test func renderSnapshots() throws {
        guard let directory = ProcessInfo.processInfo.environment["MARKDOWNKIT_SNAPSHOT_DIR"] else { return }
        for (name, markdown) in Self.samples {
            for scheme in [ColorScheme.light, .dark] {
                let view = MarkdownView(markdown)
                    .markdownTheme { $0.codeBlock.wrapsLines = true } // ImageRenderer doesn't draw ScrollView content.
                    .padding()
                    .frame(width: 390)
                    .background(scheme == .dark ? Color.black : Color.white)
                    .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                let image = try #require(renderer.cgImage)
                let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png")
                let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
                CGImageDestinationAddImage(destination, image, nil)
                #expect(CGImageDestinationFinalize(destination))
            }
        }
        // Tables draw lazily in async canvases, which ImageRenderer doesn't capture: draw directly.
        for scheme in [ColorScheme.light, .dark] {
            let theme = ResolvedTheme(theme: .default, colorScheme: scheme, dynamicTypeSize: .large)
            let document = MarkdownPipeline.prepare(MarkdownRequest(text: Self.samples[0].1, theme: theme, options: .default, isStreaming: false))
            guard case .table(let layout) = document.blocks[1].content else { continue }
            let scale: CGFloat = 2
            let size = layout.size
            let context = try #require(CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                                 bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(scheme == .dark ? CGColor(gray: 0, alpha: 1) : CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(origin: .zero, size: CGSize(width: size.width * scale, height: size.height * scale)))
            // Flip to a top-left origin like SwiftUI's Canvas.
            context.translateBy(x: 0, y: size.height * scale)
            context.scaleBy(x: scale, y: -scale)
            TableRenderer.draw(layout, columns: 0..<layout.columnCount, rows: 0..<layout.rowCount, origin: .zero, in: context)
            let image = try #require(context.makeImage())
            let url = URL(fileURLWithPath: directory).appendingPathComponent("table-direct-\(scheme == .dark ? "dark" : "light").png")
            let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, nil)
            #expect(CGImageDestinationFinalize(destination))
        }
    }
}
