import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics
import MarkdownKit

/// Deterministic sample content: chat messages with prose, code, math, emoji, images and big tables.
nonisolated enum SampleContent {
    struct Message: Identifiable, Hashable {
        let id: Int
        let isUser: Bool
        let text: String
    }

    static let words = """
    the quick brown fox jumps over lazy dog performance render layout stream token chat message table \
    column row cell swift view text cache memory scroll smooth frame budget model parser markdown inline \
    block heading paragraph list item quote code syntax theme color font image attachment emoji math
    """.split(separator: " ").map(String.init)

    struct Random {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        mutating func int(_ range: Range<Int>) -> Int { range.lowerBound + Int(next() % UInt64(range.count)) }
        mutating func pick<T>(_ items: [T]) -> T { items[int(0..<items.count)] }
    }

    static func sentence(_ rng: inout Random, words count: Int) -> String {
        var parts: [String] = []
        for i in 0..<count {
            var word = rng.pick(words)
            if i == 0 { word = word.prefix(1).uppercased() + word.dropFirst() }
            switch rng.int(0..<14) {
            case 0: word = "**\(word)**"
            case 1: word = "*\(word)*"
            case 2: word = "`\(word)`"
            case 3: if !UserDefaults.standard.bool(forKey: "nolinks") { word = "[\(word)](https://example.com/\(word))" }
            case 4: word = rng.pick([":rocket:", ":tada:", ":fire:", ":parrot:", "✅", "📈"])
            default: break
            }
            parts.append(word)
        }
        return parts.joined(separator: " ") + "."
    }

    static func paragraph(_ rng: inout Random) -> String {
        (0..<rng.int(2..<5)).map { _ in sentence(&rng, words: rng.int(8..<16)) }.joined(separator: " ")
    }

    static func table(rows: Int, columns: Int, seed: UInt64) -> String {
        var rng = Random(state: seed)
        var lines = ["| " + (0..<columns).map { "Column \($0 + 1)" }.joined(separator: " | ") + " |"]
        lines.append("|" + (0..<columns).map { $0 % 3 == 1 ? " ---: " : " --- " }.joined(separator: "|") + "|")
        for row in 0..<rows {
            lines.append("| " + (0..<columns).map { column -> String in
                switch rng.int(0..<8) {
                case 0: return String(format: "%.2f", Double(rng.int(0..<100_000)) / 100)
                case 1: return "[\(rng.pick(words))](https://example.com/r\(row)c\(column))"
                case 2: return "`\(rng.pick(words))`"
                case 3: return "**\(rng.pick(words))**"
                case 4: return "$x_{\(row)}$"
                default: return (0..<rng.int(1..<4)).map { _ in rng.pick(words) }.joined(separator: " ")
                }
            }.joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n")
    }

    static let code = """
    ```swift
    @MainActor
    final class ChatModel: ObservableObject {
        @Published private(set) var messages: [Message] = []

        func send(_ text: String) async throws {
            let reply = try await client.complete(prompt: text, maxTokens: 1_024)
            messages.append(Message(role: .assistant, text: reply)) // append reply
        }
    }
    ```
    """

    static func assistantMessage(_ index: Int) -> String {
        var rng = Random(state: UInt64(index) &* 7919)
        var parts = ["## Answer \(index + 1)", paragraph(&rng)]
        if index % 5 == 0, !UserDefaults.standard.bool(forKey: "notables") { parts.append(table(rows: 30, columns: 30, seed: UInt64(index))) }
        let defaults = UserDefaults.standard
        if index % 3 == 0, !defaults.bool(forKey: "nocode") { parts.append(code) }
        if index % 4 == 1, !defaults.bool(forKey: "nomath") {
            parts.append("The integral $\\int_0^1 x^2\\,dx = \\frac{1}{3}$ and:\n\n$$\\sum_{n=1}^{\\infty} \\frac{1}{n^2} = \\frac{\\pi^2}{6}$$")
        }
        if index % 7 == 2, !defaults.bool(forKey: "noimages"), let gif = animatedImageURL(type: .gif) {
            parts.append("Animated GIF inline ![gif](\(gif.absoluteString)) and as a block:\n\n![animation](\(gif.absoluteString))")
        }
        if index % 7 == 4, !defaults.bool(forKey: "noimages"), let png = animatedImageURL(type: .png) {
            parts.append("Animated PNG: ![apng](\(png.absoluteString))")
        }
        if !defaults.bool(forKey: "plain") {
            parts.append((0..<rng.int(2..<6)).map { _ in "- \(sentence(&rng, words: rng.int(5..<12)))" }.joined(separator: "\n"))
            parts.append("> " + paragraph(&rng))
        } else {
            parts.append(paragraph(&rng))
            parts.append(paragraph(&rng))
        }
        parts.append(paragraph(&rng))
        return parts.joined(separator: "\n\n")
    }

    static let conversation: [Message] = (0..<200).map { index in
        if index % 2 == 0 {
            var rng = Random(state: UInt64(index))
            return Message(id: index, isUser: true, text: sentence(&rng, words: 12))
        }
        return Message(id: index, isUser: false, text: assistantMessage(index / 2))
    }

    /// A long answer used by the streaming demo.
    static let streamingAnswer: String = {
        var rng = Random(state: 42)
        return [
            "# Streaming demo :rocket:",
            paragraph(&rng),
            "Here is a table that grows row by row:",
            table(rows: 12, columns: 6, seed: 9),
            code,
            "Math streams too: $E = mc^2$, and\n\n$$x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}$$",
            (1...5).map { "\($0). \(sentence(&rng, words: 10))" }.joined(separator: "\n"),
            paragraph(&rng),
            table(rows: 30, columns: 30, seed: 77),
            paragraph(&rng),
        ].joined(separator: "\n\n")
    }()

    // MARK: Animated images (generated locally, no network needed)

    nonisolated(unsafe) private static var animatedCache: [String: URL] = [:]
    private static let lock = NSLock()

    static func animatedImageURL(type: UTType) -> URL? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = animatedCache[type.identifier] { return cached }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("demo-animation.\(type.preferredFilenameExtension ?? "img")")
        let frames = 12
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, frames, nil) else { return nil }
        CGImageDestinationSetProperties(destination, (type == .gif
            ? [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
            : [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: 0]]) as CFDictionary)
        for frame in 0..<frames {
            let size = 96
            let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            let hue = CGFloat(frame) / CGFloat(frames)
            context.setFillColor(CGColor(red: hue, green: 0.5, blue: 1 - hue, alpha: 1))
            context.fillEllipse(in: CGRect(x: 8, y: 8, width: 80, height: 80))
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            let angle = hue * 2 * .pi
            context.fillEllipse(in: CGRect(x: 48 + cos(angle) * 26 - 8, y: 48 + sin(angle) * 26 - 8, width: 16, height: 16))
            let properties = type == .gif
                ? [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.08]]
                : [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGDelayTime: 0.08]]
            CGImageDestinationAddImage(destination, context.makeImage()!, properties as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { return nil }
        animatedCache[type.identifier] = url
        return url
    }

    /// `:parrot:` is an animated image emoji; others fall back to built-in shortcodes.
    static let emojiProvider: MarkdownEmojiProvider = { name in
        switch name {
        case "parrot": animatedImageURL(type: .gif).map(MarkdownEmoji.image)
        case "swift": .systemImage("swift")
        default: nil
        }
    }

    static let gallery = """
    # Gallery

    Headings, **bold**, *italic*, ~~strikethrough~~, `inline code`, [links](https://www.apple.com) and emoji :tada: :parrot: :swift:.

    ## Lists
    - Bullet with **formatting**
    - Second bullet
      - Nested bullet
        - Deeper
    - [x] Completed task
    - [ ] Open task

    1. Ordered
    2. List
    10. With wide numbers

    ## Quote
    > Blockquotes can contain *formatting*,
    > `code`, and multiple lines.

    ## Code
    \(code)

    ```python
    def fib(n: int) -> int:
        \"\"\"Return the n-th Fibonacci number.\"\"\"
        return n if n < 2 else fib(n - 1) + fib(n - 2)  # recursion
    ```

    ```json
    {"name": "MarkdownKit", "fast": true, "tables": 30}
    ```

    ## Math
    Inline $e^{i\\pi} + 1 = 0$ and display:

    $$f(x) = \\int_{-\\infty}^{\\infty} \\hat f(\\xi)\\,e^{2 \\pi i \\xi x} \\,d\\xi$$

    ## Table
    | Feature | Status | Notes |
    |:--|:-:|--:|
    | Tables | ✅ | Scroll horizontally |
    | Math | ✅ | $x^2$ in cells |
    | Links | ✅ | [tap me](https://example.com) |

    ---

    Wide table (scroll →):

    \(table(rows: 8, columns: 14, seed: 3))
    """
}
