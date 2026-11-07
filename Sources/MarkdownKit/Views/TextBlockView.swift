import SwiftUI

/// Paragraphs, headings and other inline-content blocks: a single `Text` per block.
struct TextBlockView: View {
    let text: PreparedText
    let role: TextRole
    let theme: ResolvedTheme

    var body: some View {
        let view = InlineTextView(text: text, theme: theme)
            .lineSpacing(text.lineSpacing)
            .tint(Color(theme.linkColor))
        switch role {
        case .heading(let level):
            VStack(alignment: .leading, spacing: theme.length(.em(0.3))) {
                view.accessibilityAddTraits(.isHeader)
                    .accessibilityHeading(Self.headingLevel(level))
                if theme.theme.heading(level).divider {
                    Rectangle().fill(Color(theme.ruleColor)).frame(height: 1)
                }
            }
            .padding(.bottom, theme.length(theme.theme.heading(level).spacingAfter))
        case .paragraph, .html:
            view
        }
    }

    static func headingLevel(_ level: Int) -> AccessibilityHeadingLevel {
        switch level {
        case 1: .h1
        case 2: .h2
        case 3: .h3
        case 4: .h4
        case 5: .h5
        default: .h6
        }
    }
}

/// Composes inline segments (attributed text and attachments) into one `Text`.
struct InlineTextView: View {
    let text: PreparedText
    let theme: ResolvedTheme

    var body: some View {
        if text.hasAttachments {
            AttachmentTextView(text: text, theme: theme)
        } else {
            Self.compose(text.segments) { segment in
                if case .text(let string) = segment { return Text(string) }
                return Text(verbatim: "")
            }
        }
    }

    static func compose(_ segments: [InlineSegment], _ transform: (InlineSegment) -> Text) -> Text {
        switch segments.count {
        case 0: return Text(verbatim: "")
        case 1: return transform(segments[0])
        default:
            var result = transform(segments[0])
            for segment in segments.dropFirst() {
                let next = transform(segment)
                result = Text("\(result)\(next)")
            }
            return result
        }
    }
}

/// Marks the run of an animated inline attachment so ``AnimatedAttachmentRenderer`` can draw its
/// current frame in place of the static placeholder.
struct AnimatedAttachmentAttribute: TextAttribute {
    let id: Int
}

/// Draws text normally and replaces animated attachment runs with the frame for `time`.
struct AnimatedAttachmentRenderer: TextRenderer {
    var time: TimeInterval
    let animations: [Int: AnimatedImage]
    let displayScale: CGFloat

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                if let attribute = run[AnimatedAttachmentAttribute.self], let animation = animations[attribute.id] {
                    let frame = animation.frame(at: time)
                    context.draw(Image(decorative: frame, scale: displayScale), in: run.typographicBounds.rect)
                } else {
                    context.draw(run)
                }
            }
        }
    }
}

/// Text with inline attachments: math, images and custom emoji, including animated ones.
struct AttachmentTextView: View {
    let text: PreparedText
    let theme: ResolvedTheme

    @Environment(\.markdownImageLoader) private var loader
    @Environment(\.markdownEmojiProvider) private var emojiProvider
    @Environment(\.markdownAnimatesImages) private var animates
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale
    @State private var images: [URL: MarkdownImage] = [:]
    @State private var isVisible = true

    private func emoji(_ name: String) -> MarkdownEmoji? {
        if let resolved = emojiProvider?(name) { return resolved }
        return MarkdownEmojiShortcodes.common[name].map(MarkdownEmoji.text)
    }

    private func maxPixelSize(height: CGFloat) -> CGFloat { height * displayScale * 4 }

    private func image(for url: URL, height: CGFloat) -> MarkdownImage? {
        images[url] ?? loader.cachedImage(for: url, maxPixelSize: maxPixelSize(height: height))
    }

    /// URLs to load, with the attachment height they are displayed at.
    private var pendingURLs: [URL: CGFloat] {
        var urls: [URL: CGFloat] = [:]
        for segment in text.segments {
            switch segment {
            case .image(let image):
                if let url = image.url { urls[url] = image.height }
            case .emoji(let item):
                if case .image(let url) = emoji(item.name) { urls[url] = item.size }
            default: break
            }
        }
        return urls
    }

    var body: some View {
        var animations: [Int: AnimatedImage] = [:]
        var index = 0
        let content = InlineTextView.compose(text.segments) { segment in
            defer { index += 1 }
            switch segment {
            case .text(let string):
                return Text(string)
            case .math(let math):
                return InlineAttachments.math(math)
            case .image(let item):
                guard let url = item.url, let loaded = image(for: url, height: item.height) else { return Text(item.fallback) }
                return attachment(loaded, height: item.height, id: index, animations: &animations)
                    .accessibilityLabel(item.alt)
            case .emoji(let item):
                switch emoji(item.name) {
                case .text(let string)?:
                    var attributed = AttributedString(string)
                    if let run = item.fallback.runs.first { attributed.mergeAttributes(run.attributes) }
                    return Text(attributed)
                case .systemImage(let name)?:
                    return Text(Image(systemName: name)).accessibilityLabel(item.name)
                case .image(let url)?:
                    guard let loaded = image(for: url, height: item.size) else { return Text(item.fallback) }
                    return attachment(loaded, height: item.size, id: index, animations: &animations)
                        .accessibilityLabel(item.name)
                case nil:
                    return Text(item.fallback)
                }
            }
        }
        let paused = animations.isEmpty || !animates || reduceMotion || !isVisible || scenePhase == .background
        let minimumDelay = animations.values.map(\.minimumDelay).min() ?? 0.1
        let frozenAnimations = animations
        return Group {
            if paused {
                content
            } else {
                TimelineView(.animation(minimumInterval: max(minimumDelay, 1.0 / 60))) { context in
                    content.textRenderer(AnimatedAttachmentRenderer(time: context.date.timeIntervalSinceReferenceDate,
                                                                    animations: frozenAnimations, displayScale: 1))
                }
            }
        }
        .onScrollVisibilityChange(threshold: 0.01) { isVisible = $0 }
        .task(id: Array(pendingURLs.keys).sorted { $0.absoluteString < $1.absoluteString }) {
            await loadImages()
        }
    }

    private func attachment(_ image: MarkdownImage, height: CGFloat, id: Int, animations: inout [Int: AnimatedImage]) -> Text {
        let frame = image.firstFrame
        let scale = max(CGFloat(frame.height) / max(height, 1), 0.01)
        let base = Text(Image(decorative: frame, scale: scale)).baselineOffset(-height * 0.2)
        if case .animated(let animation) = image.content {
            animations[id] = animation
            return base.customAttribute(AnimatedAttachmentAttribute(id: id))
        }
        return base
    }

    private func loadImages() async {
        await withTaskGroup(of: (URL, MarkdownImage?).self) { group in
            for (url, height) in pendingURLs where image(for: url, height: height) == nil {
                let loader = loader
                let size = maxPixelSize(height: height)
                group.addTask { (url, try? await loader.loadImage(from: url, maxPixelSize: size)) }
            }
            for await (url, image) in group {
                if let image { images[url] = image }
            }
        }
    }
}

enum InlineAttachments {
    static func math(_ math: PreparedMath) -> Text {
        guard let image = math.image else { return Text(math.fallback) }
        return Text(Image(decorative: image.cgImage, scale: image.scale))
            .baselineOffset(-math.descent)
            .accessibilityLabel(math.latex)
    }
}
