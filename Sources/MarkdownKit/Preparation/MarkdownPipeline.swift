import SwiftUI

/// A request to render a Markdown string with a resolved theme.
struct MarkdownRequest: Hashable, Sendable {
    var source: SourceText
    var theme: ResolvedTheme
    var options: MarkdownParseOptions
    var isStreaming: Bool
    /// Width the document will be laid out at, if known (enables off-main text layout).
    /// Not part of the request's identity.
    var layoutWidth: CGFloat?

    var text: String { source.string }

    init(text: String, theme: ResolvedTheme, options: MarkdownParseOptions, isStreaming: Bool, layoutWidth: CGFloat? = nil) {
        source = SourceText(text)
        self.theme = theme
        self.options = options
        self.isStreaming = isStreaming
        self.layoutWidth = layoutWidth
    }

    static func == (lhs: MarkdownRequest, rhs: MarkdownRequest) -> Bool {
        lhs.source == rhs.source && lhs.theme == rhs.theme && lhs.options == rhs.options && lhs.isStreaming == rhs.isStreaming
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(source)
        hasher.combine(theme)
        hasher.combine(options)
        hasher.combine(isStreaming)
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
        let document = MarkdownPreparer(theme: request.theme, math: math, layoutWidth: request.layoutWidth).prepare(blocks, key: request.documentKey)
        if !request.isStreaming {
            MarkdownCache.shared[request.cacheKey] = document
        }
        return document
    }

    static var defaultMathRenderer: (any MathRendering)? { SwiftMathRenderer.shared }
}

/// Serial, off-main pipeline that keeps incremental parsing state across streaming updates.
///
/// Per update, only the tail of the text is re-parsed and only blocks after the frozen prefix are
/// re-prepared; the prefix's prepared blocks are reused as is, so the cost of a streaming update does
/// not grow with the length of the message.
actor StreamingPipeline {
    private var session: StreamingSession
    private var options: MarkdownParseOptions

    init(options: MarkdownParseOptions) {
        self.options = options
        session = StreamingSession(options: options)
    }

    func prepare(_ request: MarkdownRequest) -> PreparedDocument {
        if request.options != options {
            options = request.options
            session = StreamingSession(options: options)
        }
        return session.update(request)
    }
}

/// Synchronous streaming session (same algorithm as ``StreamingPipeline``) for benchmarks and tests.
final class StreamingSession {
    private var incremental: IncrementalParser
    private var lastBlocks: [PreparedBlock] = []
    private var lastTheme: ResolvedTheme?
    private(set) var lastReusedBlocks = 0

    init(options: MarkdownParseOptions = .default) {
        incremental = IncrementalParser(parser: MarkdownParser(options: options))
    }

    func update(_ request: MarkdownRequest, math: (any MathRendering)? = MarkdownPipeline.defaultMathRenderer) -> PreparedDocument {
        if !request.isStreaming, let cached = MarkdownCache.shared[request.cacheKey] {
            incremental.reset()
            lastBlocks = cached.blocks
            lastTheme = request.theme
            return cached
        }
        let parseState = Signposts.parse.beginInterval("parse")
        let blocks = incremental.update(request.text, isStreaming: request.isStreaming)
        Signposts.parse.endInterval("parse", parseState)
        lastReusedBlocks = lastTheme == request.theme ? min(incremental.reusedBlockCount, lastBlocks.count) : 0
        let document = MarkdownPreparer(theme: request.theme, math: math, layoutWidth: request.layoutWidth)
            .prepare(blocks, key: request.documentKey, reusing: lastBlocks.prefix(lastReusedBlocks))
        lastBlocks = document.blocks
        lastTheme = request.theme
        if !request.isStreaming {
            MarkdownCache.shared[request.cacheKey] = document
        }
        return document
    }
}
