import SwiftUI

/// Renders Markdown.
///
/// ```swift
/// MarkdownView(message.text)                               // static content
/// MarkdownView(partialReply, isStreaming: true)            // streaming: pass the growing text
///     .markdownTheme(.compact)
///     .markdownCodeTheme(.github)
/// ```
///
/// Parsing and layout preparation happen off the main thread and are cached by content, theme and
/// Dynamic Type size. While streaming, only the last block is re-parsed and re-prepared on each update,
/// and unchanged blocks are skipped by SwiftUI's diffing.
public struct MarkdownView: View {
    private let text: String
    private let isStreaming: Bool

    @Environment(\.markdownTheme) private var theme
    @Environment(\.markdownParseOptions) private var options
    @Environment(\.markdownSynchronousPreparationLimit) private var synchronousLimit
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var model = MarkdownViewModel()

    /// - Parameters:
    ///   - text: Markdown source.
    ///   - isStreaming: `true` while the text is still growing (e.g. a chat reply being generated).
    ///     Enables incremental parsing and display repairs for incomplete constructs.
    public init(_ text: String, isStreaming: Bool = false) {
        self.text = text
        self.isStreaming = isStreaming
    }

    public var body: some View {
        let resolved = ResolvedThemeCache.shared.theme(theme, colorScheme: colorScheme, dynamicTypeSize: dynamicTypeSize)
        let request = MarkdownRequest(text: text, theme: resolved, options: options, isStreaming: isStreaming)
        let document = model.document(for: request, synchronousLimit: synchronousLimit)
        MarkdownDocumentView(document: document ?? .empty, theme: resolved)
            .task(id: request) { await model.update(request) }
    }
}

/// Holds the displayed document and coordinates sync/async preparation for one ``MarkdownView``.
@MainActor @Observable
final class MarkdownViewModel {
    private var revision = 0
    @ObservationIgnored private var displayed: (request: MarkdownRequest, document: PreparedDocument)?
    @ObservationIgnored private var pipeline: StreamingPipeline?
    @ObservationIgnored private var pending: MarkdownRequest?
    @ObservationIgnored private var isRunning = false

    /// Returns the document to show for `request`: the current one, a cached one, a synchronously
    /// prepared one (small inputs), or the previous one while an async preparation is pending.
    func document(for request: MarkdownRequest, synchronousLimit: Int) -> PreparedDocument? {
        _ = revision // Observe async completions.
        if let displayed, displayed.request == request { return displayed.document }
        if !request.isStreaming, let cached = MarkdownCache.shared[request.cacheKey] {
            displayed = (request, cached)
            return cached
        }
        if request.text.utf8.count <= synchronousLimit, !isRunning {
            let document = MarkdownPipeline.prepare(request)
            displayed = (request, document)
            return document
        }
        return displayed?.document
    }

    /// Prepares `request` off the main thread. Updates are coalesced: while one preparation runs, only
    /// the latest request is kept.
    func update(_ request: MarkdownRequest) async {
        if let displayed, displayed.request == request { return }
        pending = request
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        let pipeline = self.pipeline ?? StreamingPipeline(options: request.options)
        self.pipeline = pipeline
        while let next = pending {
            pending = nil
            let document = await pipeline.prepare(next)
            displayed = (next, document)
            revision &+= 1
        }
    }
}
