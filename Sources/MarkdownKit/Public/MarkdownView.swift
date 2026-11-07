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
///
/// For very long messages inside a `LazyVStack`, use ``MarkdownBlocks`` so each block becomes its own
/// lazily created row.
public struct MarkdownView: View {
    private let text: String
    private let isStreaming: Bool
    private var source = MarkdownSource()

    /// - Parameters:
    ///   - text: Markdown source.
    ///   - isStreaming: `true` while the text is still growing (e.g. a chat reply being generated).
    ///     Enables incremental parsing and display repairs for incomplete constructs.
    public init(_ text: String, isStreaming: Bool = false) {
        self.text = text
        self.isStreaming = isStreaming
    }

    public var body: some View {
        let resolved = source.resolve(text, isStreaming: isStreaming)
        let model = source.model
        MarkdownDocumentView(document: resolved.document, theme: resolved.theme,
                             showsCursor: isStreaming && source.showsCursor)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { model.layoutWidth = $0 }
            .task(id: resolved.request) { await model.update(resolved.request) }
    }
}

/// Renders Markdown as a flat list of block views, for embedding directly in a `LazyVStack`.
///
/// ```swift
/// ScrollView {
///     LazyVStack(alignment: .leading) {
///         ForEach(messages) { message in
///             MarkdownBlocks(message.text, isStreaming: message.isStreaming)
///         }
///     }
/// }
/// ```
///
/// Each block is a separate child of the lazy stack, so a message with many tables or a long code
/// listing only creates the views that are on screen.
public struct MarkdownBlocks: View {
    private let text: String
    private let isStreaming: Bool
    private var source = MarkdownSource()

    public init(_ text: String, isStreaming: Bool = false) {
        self.text = text
        self.isStreaming = isStreaming
    }

    public var body: some View {
        let resolved = source.resolve(text, isStreaming: isStreaming)
        let blocks = resolved.document.blocks
        let spacing = resolved.theme.length(resolved.theme.theme.blockSpacing)
        let lastID = blocks.last?.id
        let model = source.model
        if blocks.isEmpty {
            Color.clear.frame(height: 1)
                .task(id: resolved.request) { await model.update(resolved.request) }
        } else {
            ForEach(blocks) { block in
                let isLast = block.id == lastID
                BlockView(block: block, theme: resolved.theme, isFirst: block.id == 0,
                          showsCursor: isLast && isStreaming && source.showsCursor)
                    .equatable()
                    .padding(.top, block.id == 0 ? 0 : spacing)
                    .modifier(UpdateTask(isActive: isLast, request: resolved.request, model: model))
            }
        }
    }
}

/// Runs the preparation task on one row only (the last one, which is on screen while streaming).
private struct UpdateTask: ViewModifier {
    let isActive: Bool
    let request: MarkdownRequest
    let model: MarkdownViewModel

    func body(content: Content) -> some View {
        if isActive {
            content
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { model.layoutWidth = $0 }
                .task(id: request) { await model.update(request) }
        } else {
            content
        }
    }
}

/// Environment inputs and per-view state shared by ``MarkdownView`` and ``MarkdownBlocks``.
@MainActor
struct MarkdownSource: DynamicProperty {
    @Environment(\.markdownTheme) private var theme
    @Environment(\.markdownParseOptions) private var options
    @Environment(\.markdownSynchronousPreparationLimit) private var synchronousLimit
    @Environment(\.markdownStreamingCursor) var showsCursor
    @Environment(\.markdownTextRenderer) private var textRenderer
    @Environment(\.markdownEmojiProvider) private var emojiProvider
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State var model = MarkdownViewModel()

    struct Resolved {
        var document: PreparedDocument
        var theme: ResolvedTheme
        var request: MarkdownRequest
    }

    @MainActor
    func resolve(_ text: String, isStreaming: Bool) -> Resolved {
        let resolvedTheme = ResolvedThemeCache.shared.theme(theme, colorScheme: colorScheme, dynamicTypeSize: dynamicTypeSize,
                                                            textRenderer: textRenderer)
        var options = options
        options.hasEmojiProvider = emojiProvider != nil
        let request = MarkdownRequest(text: text, theme: resolvedTheme, options: options, isStreaming: isStreaming,
                                      layoutWidth: model.layoutWidth)
        let document = model.document(for: request, synchronousLimit: synchronousLimit) ?? .empty
        return Resolved(document: document, theme: resolvedTheme, request: request)
    }
}

/// Holds the displayed document and coordinates sync/async preparation for one view.
@MainActor @Observable
final class MarkdownViewModel {
    private var revision = 0
    @ObservationIgnored private var displayed: (request: MarkdownRequest, document: PreparedDocument)?
    @ObservationIgnored private var pipeline: StreamingPipeline?
    @ObservationIgnored private var pending: MarkdownRequest?
    @ObservationIgnored private var isRunning = false
    /// Last measured width; lets the pipeline typeset text off the main thread.
    @ObservationIgnored var layoutWidth: CGFloat?

    /// Returns the document to show for `request`: the current one, a cached one, a synchronously
    /// prepared one (small inputs on first display), or the previous one while an async preparation
    /// is pending. Streaming updates after the first display always go through the async pipeline,
    /// keeping the main thread free.
    func document(for request: MarkdownRequest, synchronousLimit: Int) -> PreparedDocument? {
        _ = revision // Observe async completions.
        if let displayed, displayed.request == request { return displayed.document }
        if !request.isStreaming, let cached = MarkdownCache.shared[request.cacheKey] {
            displayed = (request, cached)
            return cached
        }
        let isStreamingUpdate = request.isStreaming && displayed != nil
        if !isStreamingUpdate, request.source.byteCount <= synchronousLimit, !isRunning {
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
