import SwiftUI

extension EnvironmentValues {
    /// The theme used by ``MarkdownView``.
    @Entry public var markdownTheme: MarkdownTheme = .default
    /// Parsing options used by ``MarkdownView``.
    @Entry public var markdownParseOptions: MarkdownParseOptions = .default
    /// Inputs up to this many UTF-8 bytes are prepared synchronously on first display when they are
    /// not cached (no placeholder flash). Larger inputs are prepared off the main thread.
    @Entry public var markdownSynchronousPreparationLimit: Int = 8 * 1024
    /// Loads images and image emoji.
    @Entry public var markdownImageLoader: any MarkdownImageLoader = DefaultMarkdownImageLoader.shared
    /// Resolves `:shortcode:` custom emoji. Falls back to ``MarkdownEmojiShortcodes/common``.
    @Entry public var markdownEmojiProvider: MarkdownEmojiProvider? = nil
    /// Plays animated images (GIF, APNG, WebP). Animations also pause with Reduce Motion and off screen.
    @Entry public var markdownAnimatesImages: Bool = true
}

extension View {
    /// Sets the theme for Markdown views in this hierarchy.
    public func markdownTheme(_ theme: MarkdownTheme) -> some View {
        environment(\.markdownTheme, theme)
    }

    /// Modifies the current Markdown theme in place.
    ///
    /// ```swift
    /// MarkdownView(text)
    ///     .markdownTheme { $0.link.color = .purple }
    /// ```
    public func markdownTheme(_ transform: @escaping (inout MarkdownTheme) -> Void) -> some View {
        transformEnvironment(\.markdownTheme, transform: transform)
    }

    /// Base text style: size at the default Dynamic Type size, font and color.
    public func markdownTextStyle(baseSize: CGFloat? = nil, font: MarkdownFont = .body, color: Color = .primary,
                                  lineSpacing: MarkdownLength = .em(0.2)) -> some View {
        markdownTheme { theme in
            theme.text.baseSize = baseSize
            theme.text.font = font
            theme.text.color = color
            theme.text.lineSpacing = lineSpacing
        }
    }

    /// Style for headings of `level` (1...6).
    public func markdownHeadingStyle(level: Int, _ style: MarkdownTheme.Heading) -> some View {
        markdownTheme { theme in
            guard (1...theme.headings.count).contains(level) else { return }
            theme.headings[level - 1] = style
        }
    }

    public func markdownLinkStyle(_ style: MarkdownTheme.Link) -> some View {
        markdownTheme { $0.link = style }
    }

    public func markdownInlineCodeStyle(_ style: MarkdownTheme.InlineCode) -> some View {
        markdownTheme { $0.inlineCode = style }
    }

    public func markdownCodeBlockStyle(_ style: MarkdownTheme.CodeBlock) -> some View {
        markdownTheme { $0.codeBlock = style }
    }

    /// Syntax highlighting colors for code blocks.
    public func markdownCodeTheme(_ codeTheme: CodeTheme) -> some View {
        markdownTheme { $0.codeBlock.theme = codeTheme }
    }

    public func markdownBlockquoteStyle(_ style: MarkdownTheme.Blockquote) -> some View {
        markdownTheme { $0.blockquote = style }
    }

    public func markdownListStyle(_ style: MarkdownTheme.List) -> some View {
        markdownTheme { $0.list = style }
    }

    public func markdownTableStyle(_ style: MarkdownTheme.Table) -> some View {
        markdownTheme { $0.table = style }
    }

    public func markdownThematicBreakStyle(_ style: MarkdownTheme.ThematicBreak) -> some View {
        markdownTheme { $0.thematicBreak = style }
    }

    public func markdownImageStyle(_ style: MarkdownTheme.Image) -> some View {
        markdownTheme { $0.image = style }
    }

    public func markdownMathStyle(_ style: MarkdownTheme.Math) -> some View {
        markdownTheme { $0.math = style }
    }

    /// Vertical space between blocks.
    public func markdownBlockSpacing(_ spacing: MarkdownLength) -> some View {
        markdownTheme { $0.blockSpacing = spacing }
    }

    /// Enables or disables math (`$…$`, `$$…$$`, `\(…\)`, `\[…\]`) and `:emoji:` recognition.
    public func markdownParseOptions(_ options: MarkdownParseOptions) -> some View {
        environment(\.markdownParseOptions, options)
    }

    /// Handles taps on links (in text and tables). Return `.handled` to stop default handling.
    public func onMarkdownLinkTap(_ handler: @escaping (URL) -> OpenURLAction.Result) -> some View {
        environment(\.openURL, OpenURLAction(handler: handler))
    }

    /// Uses a custom image loader for Markdown images and image emoji.
    public func markdownImageLoader(_ loader: any MarkdownImageLoader) -> some View {
        environment(\.markdownImageLoader, loader)
    }

    /// Resolves `:shortcode:` custom emoji to text, images (static or animated) or SF Symbols.
    public func markdownEmojiProvider(_ provider: @escaping MarkdownEmojiProvider) -> some View {
        environment(\.markdownEmojiProvider, provider)
    }

    /// Enables or disables animated image playback.
    public func markdownAnimatesImages(_ enabled: Bool) -> some View {
        environment(\.markdownAnimatesImages, enabled)
    }

    /// See ``SwiftUICore/EnvironmentValues/markdownSynchronousPreparationLimit``.
    public func markdownSynchronousPreparationLimit(_ bytes: Int) -> some View {
        environment(\.markdownSynchronousPreparationLimit, bytes)
    }
}
