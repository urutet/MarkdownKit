import SwiftUI

/// Warms the Markdown cache ahead of display, so cells in a chat list render instantly (no async hop,
/// no placeholder) when they scroll into view.
///
/// ```swift
/// // When messages arrive (e.g. loading a conversation):
/// await MarkdownPrefetcher.prefetch(messages.map(\.text))
///
/// // Or declaratively, using the view's current theme and Dynamic Type size:
/// ChatList(messages).markdownPrefetch(messages.map(\.text))
/// ```
public enum MarkdownPrefetcher {
    /// Parses and prepares `texts` concurrently off the main thread.
    ///
    /// - Parameter width: The width the messages will be displayed at, if known. Text is then also
    ///   typeset in the background, leaving almost nothing for the main thread at display time.
    @MainActor
    public static func prefetch(_ texts: [String], width: CGFloat? = nil, theme: MarkdownTheme = .default,
                                colorScheme: ColorScheme = .light, dynamicTypeSize: DynamicTypeSize = .large,
                                textRenderer: MarkdownTextRenderer = .default,
                                options: MarkdownParseOptions = .default) async {
        let resolved = ResolvedThemeCache.shared.theme(theme, colorScheme: colorScheme, dynamicTypeSize: dynamicTypeSize,
                                                       textRenderer: textRenderer)
        await prefetch(texts, theme: resolved, options: options, width: width)
    }

    static func prefetch(_ texts: [String], theme: ResolvedTheme, options: MarkdownParseOptions, width: CGFloat? = nil) async {
        let requests = texts.map { MarkdownRequest(text: $0, theme: theme, options: options, isStreaming: false, layoutWidth: width) }
            .filter { MarkdownCache.shared[$0.cacheKey] == nil }
        guard !requests.isEmpty else { return }
        let width = max(1, Parallel.processorCount - 1)
        await withTaskGroup(of: Void.self) { group in
            var iterator = requests.makeIterator()
            for _ in 0..<width {
                guard let request = iterator.next() else { break }
                group.addTask(priority: .utility) { _ = MarkdownPipeline.prepare(request) }
            }
            while await group.next() != nil {
                guard let request = iterator.next() else { continue }
                group.addTask(priority: .utility) { _ = MarkdownPipeline.prepare(request) }
            }
        }
    }
}

private struct PrefetchModifier: ViewModifier {
    let texts: [String]
    let width: CGFloat?
    @Environment(\.markdownTheme) private var theme
    @Environment(\.markdownParseOptions) private var options
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.markdownTextRenderer) private var textRenderer
    @Environment(\.markdownEmojiProvider) private var emojiProvider

    func body(content: Content) -> some View {
        content.task(id: PrefetchKey(texts: texts, theme: theme, colorScheme: colorScheme, dynamicTypeSize: dynamicTypeSize,
                                     textRenderer: textRenderer, options: options, hasProvider: emojiProvider != nil)) {
            let resolved = ResolvedThemeCache.shared.theme(theme, colorScheme: colorScheme, dynamicTypeSize: dynamicTypeSize,
                                                           textRenderer: textRenderer)
            var options = options
            options.hasEmojiProvider = emojiProvider != nil
            await MarkdownPrefetcher.prefetch(texts, theme: resolved, options: options, width: width)
        }
    }

    private struct PrefetchKey: Equatable {
        var texts: [String]
        var theme: MarkdownTheme
        var colorScheme: ColorScheme
        var dynamicTypeSize: DynamicTypeSize
        var textRenderer: MarkdownTextRenderer
        var options: MarkdownParseOptions
        var hasProvider: Bool
    }
}

extension View {
    /// Prepares `texts` in the background with this view's Markdown environment (theme, color scheme,
    /// Dynamic Type size), so ``MarkdownView``s showing them render from cache.
    ///
    /// - Parameter width: Display width of the messages, if known, to also typeset text in the background.
    public func markdownPrefetch(_ texts: [String], width: CGFloat? = nil) -> some View {
        modifier(PrefetchModifier(texts: texts, width: width))
    }
}
