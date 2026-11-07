import SwiftUI
import Testing
@testable import MarkdownKit

@MainActor
@Suite(.serialized, .tags(.benchmark))
struct MathBenchmarks {
    let theme = ResolvedTheme(theme: .default, colorScheme: .light, dynamicTypeSize: .large)

    @Test(arguments: MathRendererKind.allCases)
    func render300Expressions(renderer kind: MathRendererKind) {
        let renderer = kind.renderer
        var round = 0
        let result = Benchmark.measure("render 300 formulas \(kind) (cold)", iterations: Benchmark.iterations(5)) {
            round += 1
            for index in 0..<300 {
                let latex = Fixtures.mathExpressions[index % Fixtures.mathExpressions.count] + "+\(index)+\(round)"
                _ = renderer.render(latex: latex, display: index % 3 == 0, fontSize: 17, color: theme.textColor, font: .latinModern)
            }
        }
        Benchmark.expect(result.median, lessThan: 400, "300 formulas")
    }

    @Test func prepareMathDocument() {
        let request = MarkdownRequest(text: Fixtures.mathDocument(count: 300), theme: theme, options: .default, isStreaming: false)
        _ = MarkdownPipeline.prepare(request) // warm the formula cache like a real chat
        let result = Benchmark.measure("parse+prepare 300-formula doc (formulas cached)", iterations: Benchmark.iterations(10),
                                       setup: { MarkdownCache.shared.removeAll() }) {
            _ = MarkdownPipeline.prepare(request)
        }
        Benchmark.expect(result.median, lessThan: 40, "prepare math doc (warm formulas)")
    }
}
