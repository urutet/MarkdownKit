import Foundation

/// Deterministic Markdown fixtures for benchmarks.
enum Fixtures {
    /// SplitMix64: fast deterministic generator.
    struct Random {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        mutating func int(_ range: Range<Int>) -> Int { range.lowerBound + Int(next() % UInt64(range.count)) }
        mutating func chance(_ p: Double) -> Bool { Double(next() % 10_000) / 10_000 < p }
        mutating func pick<T>(_ items: [T]) -> T { items[int(0..<items.count)] }
    }

    static let words = """
    the quick brown fox jumps over lazy dog performance render layout stream token chat message \
    table column row cell swift view text attribute cache memory scroll smooth frame budget model \
    parser markdown inline block heading paragraph list item quote code syntax theme color font \
    image attachment emoji math formula latency throughput network device simulator benchmark
    """.split(separator: " ").map(String.init)

    static let emoji = ["🚀", "✅", "🔥", "📈", "🧪", "💡", "🎉", "⚠️", "👍", "🤖"]

    static func sentence(_ rng: inout Random, words count: Int, richness: Double = 0.15) -> String {
        var parts: [String] = []
        for i in 0..<count {
            var word = rng.pick(words)
            if i == 0 { word = word.prefix(1).uppercased() + word.dropFirst() }
            if rng.chance(richness) {
                switch rng.int(0..<7) {
                case 0: word = "**\(word)**"
                case 1: word = "*\(word)*"
                case 2: word = "`\(word)()`"
                case 3: word = "[\(word)](https://example.com/\(word)/\(rng.int(0..<1000)))"
                case 4: word = rng.pick(emoji)
                case 5: word = "~~\(word)~~"
                default: word = "$x_{\(rng.int(0..<9))}^2$"
                }
            }
            parts.append(word)
        }
        return parts.joined(separator: " ") + "."
    }

    static func paragraph(_ rng: inout Random) -> String {
        (0..<rng.int(2..<5)).map { _ in sentence(&rng, words: rng.int(8..<18)) }.joined(separator: " ")
    }

    static func cell(_ rng: inout Random, row: Int, column: Int) -> String {
        switch rng.int(0..<10) {
        case 0: return String(format: "%.2f", Double(rng.int(0..<100_000)) / 100)
        case 1: return "[\(rng.pick(words))](https://example.com/r\(row)c\(column))"
        case 2: return "`\(rng.pick(words))`"
        case 3: return "**\(rng.pick(words))**"
        case 4: return rng.pick(emoji) + " " + rng.pick(words)
        case 5: return sentence(&rng, words: rng.int(4..<12), richness: 0)
        default: return (0..<rng.int(1..<3)).map { _ in rng.pick(words) }.joined(separator: " ")
        }
    }

    /// A GFM table with `rows` body rows and `columns` columns.
    static func table(rows: Int = 30, columns: Int = 30, seed: UInt64 = 1) -> String {
        var rng = Random(seed: seed)
        var lines: [String] = []
        lines.append("| " + (0..<columns).map { "Column \($0 + 1)" }.joined(separator: " | ") + " |")
        lines.append("|" + (0..<columns).map { $0 % 3 == 1 ? " ---: " : " --- " }.joined(separator: "|") + "|")
        for row in 0..<rows {
            lines.append("| " + (0..<columns).map { cell(&rng, row: row, column: $0) }.joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n")
    }

    static func codeBlock(_ rng: inout Random, lines: Int = 12) -> String {
        var code = ["```swift"]
        for i in 0..<lines {
            switch i % 4 {
            case 0: code.append("func \(rng.pick(words))(_ value: Int) -> String {")
            case 1: code.append("    let result = value * \(rng.int(1..<100)) // \(rng.pick(words))")
            case 2: code.append("    return \"\\(result) \(rng.pick(words))\"")
            default: code.append("}")
            }
        }
        code.append("```")
        return code.joined(separator: "\n")
    }

    /// A chat-style message mixing every construct, approximately `bytes` long.
    static func chatMessage(bytes: Int, seed: UInt64 = 7, includeTables: Bool = true) -> String {
        var rng = Random(seed: seed)
        var parts: [String] = []
        var size = 0
        var section = 0
        while size < bytes {
            var part: String
            switch section % 9 {
            case 0: part = "## \(sentence(&rng, words: 4, richness: 0))"
            case 1, 2: part = paragraph(&rng)
            case 3: part = (0..<rng.int(3..<7)).map { _ in "- \(sentence(&rng, words: rng.int(5..<12)))" }.joined(separator: "\n")
            case 4: part = codeBlock(&rng, lines: rng.int(6..<20))
            case 5: part = "> " + paragraph(&rng)
            case 6: part = includeTables ? table(rows: 6, columns: 4, seed: rng.next()) : paragraph(&rng)
            case 7: part = "$$\n\\sum_{i=1}^{n} i = \\frac{n(n+1)}{2}\n$$"
            default: part = (1...rng.int(3..<6)).map { n in "\(n). \(sentence(&rng, words: rng.int(5..<10)))" }.joined(separator: "\n")
            }
            parts.append(part)
            size += part.utf8.count + 2
            section += 1
        }
        return parts.joined(separator: "\n\n")
    }

    /// Prose and links interleaved with `tableCount` tables of `rows`×`columns`.
    static func tableHeavyDocument(tableCount: Int = 10, rows: Int = 30, columns: Int = 30) -> String {
        var rng = Random(seed: 42)
        var parts: [String] = ["# Quarterly report"]
        for index in 0..<tableCount {
            parts.append("## Table \(index + 1)")
            parts.append(paragraph(&rng))
            parts.append(table(rows: rows, columns: columns, seed: UInt64(index + 100)))
            parts.append(paragraph(&rng))
        }
        return parts.joined(separator: "\n\n")
    }

    static func swiftSource(lines: Int) -> String {
        var rng = Random(seed: 3)
        var out: [String] = []
        out.reserveCapacity(lines)
        while out.count < lines {
            let name = rng.pick(words)
            out.append("/// Documentation for \(name).")
            out.append("@MainActor public final class \(name.capitalized)Model: ObservableObject {")
            out.append("    @Published var items: [String] = [\"\(name)\", \"\(rng.pick(words))\"]")
            out.append("    private let limit = \(rng.int(1..<10_000)) /* block comment */")
            out.append("    func update(_ value: Double, flag: Bool = true) async throws -> Int {")
            out.append("        guard flag else { return 0x\(String(rng.int(0..<65535), radix: 16)) }")
            out.append("        let text = \"value: \\(value) \(name)\" // trailing comment")
            out.append("        return items.filter { $0.count > limit }.map(\\.count).reduce(0, +)")
            out.append("    }")
            out.append("}")
        }
        return out.prefix(lines).joined(separator: "\n")
    }

    static let mathExpressions = [
        "e^{i\\pi} + 1 = 0",
        "\\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}",
        "\\int_0^\\infty e^{-x^2} dx = \\frac{\\sqrt{\\pi}}{2}",
        "\\sum_{n=1}^{\\infty} \\frac{1}{n^2} = \\frac{\\pi^2}{6}",
        "\\mathbf{A}\\mathbf{x} = \\lambda \\mathbf{x}",
        "f(x) = \\begin{cases} x^2 & x \\ge 0 \\\\ -x & x < 0 \\end{cases}",
        "\\nabla \\cdot \\vec{E} = \\frac{\\rho}{\\epsilon_0}",
        "\\lim_{h \\to 0} \\frac{f(x+h) - f(x)}{h}",
    ]

    static func mathDocument(count: Int) -> String {
        var rng = Random(seed: 9)
        var parts: [String] = []
        for i in 0..<count {
            let expression = mathExpressions[i % mathExpressions.count]
            if i % 3 == 0 {
                parts.append("$$\n\(expression)\n$$")
            } else {
                parts.append("\(sentence(&rng, words: 6, richness: 0)) Inline $\(expression)$ in text.")
            }
        }
        return parts.joined(separator: "\n\n")
    }
}
