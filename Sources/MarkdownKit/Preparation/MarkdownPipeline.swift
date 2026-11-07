import SwiftUI

/// A request to render a Markdown string with a resolved theme.
struct MarkdownRequest: Hashable, Sendable {
    var source: SourceText
    var theme: ResolvedTheme
    var options: MarkdownParseOptions
    var isStreaming: Bool

    var text: String { source.string }

    init(text: String, theme: ResolvedTheme, options: MarkdownParseOptions, isStreaming: Bool) {
        source = SourceText(text)
        self.theme = theme
        self.options = options
        self.isStreaming = isStreaming
    }

    var cacheKey: MarkdownCache.Key {
        MarkdownCache.Key(text: source, theme: theme, options: options)
    }

    var documentKey: Int {
        var hasher = Hasher()
        hasher.combine(cacheKey)
        hasher.combine(isStreaming)
        return hasher.finalize()
    }
}

/// Stateless parse + prepare.
enum MarkdownPipeline {
    static func prepare(_ request: MarkdownRequest, incremental: IncrementalParser? = nil,
                        math: (any MathRendering)? = defaultMathRenderer) -> PreparedDocument {
        if !request.isStreaming, let cached = MarkdownCache.shared[request.cacheKey] {
            return cached
        }
        let parseState = Signposts.parse.beginInterval("parse")
        let blocks: [MarkdownBlock]
        if let incremental {
            blocks = incremental.update(request.text, isStreaming: request.isStreaming)
        } else if request.isStreaming {
            blocks = IncrementalParser(parser: MarkdownParser(options: request.options)).update(request.text, isStreaming: true)
        } else {
            blocks = MarkdownParser(options: request.options).parse(request.text).blocks
        }
        Signposts.parse.endInterval("parse", parseState)
        let document = MarkdownPreparer(theme: request.theme, math: math).prepare(blocks, key: request.documentKey)
        if !request.isStreaming {
            MarkdownCache.shared[request.cacheKey] = document
        }
        return document
    }

    static var defaultMathRenderer: (any MathRendering)? { nil }
}

/// Serial, off-main pipeline that keeps incremental parsing state across streaming updates.
actor StreamingPipeline {
    private var incremental: IncrementalParser
    private var options: MarkdownParseOptions

    init(options: MarkdownParseOptions) {
        self.options = options
        incremental = IncrementalParser(parser: MarkdownParser(options: options))
    }

    func prepare(_ request: MarkdownRequest) -> PreparedDocument {
        if request.options != options {
            options = request.options
            incremental = IncrementalParser(parser: MarkdownParser(options: options))
        }
        return MarkdownPipeline.prepare(request, incremental: incremental)
    }
}
