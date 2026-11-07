import SwiftUI
import CoreText

/// Shared CoreText drawing into top-left-origin (SwiftUI `Canvas`) contexts.
enum CoreTextDrawing {
    static func drawText(lines: [TableLayout.Line], decorations: [TableLayout.Decoration], in cg: CGContext) {
        for decoration in decorations where decoration.kind == .background {
            cg.setFillColor(decoration.color)
            cg.addPath(CGPath(roundedRect: decoration.rect, cornerWidth: 3, cornerHeight: 3, transform: nil))
            cg.fillPath()
        }
        cg.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        for line in lines {
            cg.textPosition = line.origin
            CTLineDraw(line.line, cg)
        }
        for decoration in decorations where decoration.kind == .strikethrough {
            cg.setFillColor(decoration.color)
            cg.fill(decoration.rect)
        }
    }

    /// Draws an image upright in a flipped (top-left origin) context.
    static func drawImage(_ image: CGImage, in rect: CGRect, context cg: CGContext) {
        cg.saveGState()
        cg.translateBy(x: rect.minX, y: rect.maxY)
        cg.scaleBy(x: 1, y: -1)
        cg.interpolationQuality = .high
        cg.draw(image, in: CGRect(origin: .zero, size: rect.size))
        cg.restoreGState()
    }
}

/// Sizes a single `Canvas` child from a ``RichText`` layout for the proposed width.
struct RichTextLayout: Layout {
    let text: RichText
    /// Changes when attachment sizes change, so SwiftUI re-measures.
    var version: CGFloat = 0
    /// Leading space reserved for a list marker (hanging indent).
    var indent: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let width = proposal.width, width.isFinite else {
            let natural = text.naturalLayout().size
            return CGSize(width: natural.width + indent, height: natural.height)
        }
        if width - indent <= 1 { return CGSize(width: width, height: text.minimumLineHeight) }
        return CGSize(width: width, height: text.layout(width: width - indent).size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
        }
    }
}

/// What an attachment shows at draw time.
enum ResolvedAttachment: @unchecked Sendable {
    case image(CGImage)
    case animated(AnimatedImage)
    case text(String)
    case symbol(String)
}

/// A text block typeset with CoreText (off the main thread when the width is known in advance) and
/// drawn in a `Canvas`. About 8× cheaper to lay out than SwiftUI `Text` for rich paragraphs.
struct RichTextView: View {
    let text: RichText
    let theme: ResolvedTheme
    var showsCursor = false
    /// List marker drawn in the hanging indent, right-aligned in `markerWidth`.
    var marker: ListMarker? = nil
    var indent: CGFloat = 0
    var markerWidth: CGFloat = 0

    var body: some View {
        let needsRuntimeAttachments = text.attachments.contains {
            if case .image = $0.content { return false }
            return true
        }
        if needsRuntimeAttachments {
            AttachmentRichTextView(text: text, theme: theme, showsCursor: showsCursor, marker: marker,
                                   indent: indent, markerWidth: markerWidth)
        } else {
            // Lightweight path: no state, no environment reads, no tasks.
            Self.core(text: text, theme: theme, resolved: [:], showsCursor: showsCursor,
                      marker: marker, indent: indent, markerWidth: markerWidth, animated: false)
        }
    }

    struct MarkerInfo {
        let marker: ListMarker
        let width: CGFloat
    }

    @ViewBuilder
    static func core(text: RichText, theme: ResolvedTheme, resolved: [Int: ResolvedAttachment], showsCursor: Bool,
                     marker: ListMarker?, indent: CGFloat, markerWidth: CGFloat, animated: Bool) -> some View {
        let cursorColor = showsCursor ? theme.secondaryColor.cgColor : nil
        let textColor = theme.textColor
        let markerInfo = marker.map { MarkerInfo(marker: $0, width: markerWidth) }
        RichTextLayout(text: text, version: text.attachments.reduce(0) { $0 + $1.width }, indent: indent) {
            if animated {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    canvas(text: text, resolved: resolved, time: context.date.timeIntervalSinceReferenceDate,
                           cursorColor: cursorColor, textColor: textColor, indent: indent, marker: markerInfo)
                }
            } else {
                canvas(text: text, resolved: resolved, time: 0, cursorColor: cursorColor, textColor: textColor,
                       indent: indent, marker: markerInfo)
            }
        }
        // Expose text baselines so lists align markers with the first line.
        .alignmentGuide(.firstTextBaseline) { dimensions in
            text.layout(width: dimensions.width - indent).lines.first?.origin.y ?? dimensions[.bottom]
        }
        .alignmentGuide(.lastTextBaseline) { dimensions in
            text.layout(width: dimensions.width - indent).lines.last?.origin.y ?? dimensions[.bottom]
        }
        .accessibilityElement()
        .accessibilityLabel(text.plainText)
        .modifier(LinkInteraction(text: text, indent: indent))
    }

    private static func canvas(text: RichText, resolved: [Int: ResolvedAttachment], time: TimeInterval,
                               cursorColor: CGColor?, textColor: Color.Resolved, indent: CGFloat,
                               marker: MarkerInfo?) -> some View {
        Canvas(rendersAsynchronously: false) { context, size in
            draw(text: text, resolved: resolved, time: time, cursorColor: cursorColor, textColor: textColor,
                 indent: indent, marker: marker, context: &context, size: size)
        }
    }

    private static func draw(text: RichText, resolved: [Int: ResolvedAttachment], time: TimeInterval,
                             cursorColor: CGColor?, textColor: Color.Resolved, indent: CGFloat,
                             marker: MarkerInfo?, context: inout GraphicsContext, size: CGSize) {
        let layout = text.layout(width: size.width - indent)
        if let marker, let firstBaseline = layout.lines.first?.origin.y {
            let markerText: Text = switch marker.marker {
            case .text(let string): Text(string)
            case .checkbox(let checked, let size, let color):
                Text(Image(systemName: checked ? "checkmark.square.fill" : "square"))
                    .font(.system(size: size * 0.95))
                    .foregroundStyle(Color(color))
            }
            let resolvedMarker = context.resolve(markerText)
            let markerSize = resolvedMarker.measure(in: CGSize(width: 1000, height: 1000))
            let baseline = resolvedMarker.firstBaseline(in: markerSize)
            context.draw(resolvedMarker, in: CGRect(x: marker.width - markerSize.width, y: firstBaseline - baseline,
                                                    width: markerSize.width, height: markerSize.height))
        }
        context.translateBy(x: indent, y: 0)
        context.withCGContext { cg in
            CoreTextDrawing.drawText(lines: layout.lines, decorations: layout.decorations, in: cg)
            for item in layout.attachments {
                switch item.attachment.content {
                case .image(let image, _):
                    CoreTextDrawing.drawImage(image.cgImage, in: item.rect, context: cg)
                case .emoji, .remoteImage:
                    switch resolved[item.attachment.id] {
                    case .image(let image)?: CoreTextDrawing.drawImage(image, in: item.rect, context: cg)
                    case .animated(let animation)?: CoreTextDrawing.drawImage(animation.frame(at: time), in: item.rect, context: cg)
                    default: break
                    }
                }
            }
            if let cursorColor {
                let diameter = text.fontSize * 0.55
                let center = CGPoint(x: layout.lastLineEnd.x + diameter, y: layout.lastLineEnd.y - layout.lastLineAscent * 0.35)
                cg.setFillColor(cursorColor)
                cg.fillEllipse(in: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter))
            }
        }
        // Text and symbol attachments go through SwiftUI so they get proper font fallback.
        for item in layout.attachments {
            switch resolved[item.attachment.id] {
            case .text(let string)?:
                let resolvedText = context.resolve(Text(verbatim: string).font(.system(size: item.rect.height * 0.8)))
                context.draw(resolvedText, at: CGPoint(x: item.rect.midX, y: item.rect.midY), anchor: .center)
            case .symbol(let name)?:
                var image = context.resolve(Image(systemName: name))
                image.shading = .color(Color(textColor))
                context.draw(image, in: item.rect)
            default:
                break
            }
        }
    }
}

/// Rich text whose custom emoji or images are resolved and loaded at display time.
private struct AttachmentRichTextView: View {
    let text: RichText
    let theme: ResolvedTheme
    var showsCursor = false
    var marker: ListMarker? = nil
    var indent: CGFloat = 0
    var markerWidth: CGFloat = 0

    @Environment(\.markdownImageLoader) private var loader
    @Environment(\.markdownEmojiProvider) private var emojiProvider
    @Environment(\.markdownAnimatesImages) private var animates
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale
    @State private var images: [URL: MarkdownImage] = [:]
    @State private var isVisible = true

    var body: some View {
        let resolved = resolveAttachments()
        let hasAnimation = resolved.values.contains { if case .animated = $0 { return true }; return false }
        let animated = hasAnimation && animates && !reduceMotion && isVisible && scenePhase != .background
        RichTextView.core(text: text, theme: theme, resolved: resolved, showsCursor: showsCursor,
                          marker: marker, indent: indent, markerWidth: markerWidth, animated: animated)
            .onScrollVisibilityChange(threshold: 0.01) { isVisible = $0 }
            .task(id: pendingKey) { await loadImages() }
    }

    // MARK: Attachments

    private func emoji(_ name: String) -> MarkdownEmoji? {
        if let resolved = emojiProvider?(name) { return resolved }
        return MarkdownEmojiShortcodes.common[name].map(MarkdownEmoji.text)
    }

    private func maxPixelSize(_ attachment: CoreTextAttachment) -> CGFloat {
        (attachment.ascent + attachment.descent) * displayScale * 4
    }

    private func url(for attachment: CoreTextAttachment) -> URL? {
        switch attachment.content {
        case .remoteImage(let url, _): url
        case .emoji(let name, _): if case .image(let url)? = emoji(name) { url } else { nil }
        case .image: nil
        }
    }

    private func loaded(_ url: URL, for attachment: CoreTextAttachment) -> MarkdownImage? {
        images[url] ?? loader.cachedImage(for: url, maxPixelSize: maxPixelSize(attachment))
    }

    private func resolveAttachments() -> [Int: ResolvedAttachment] {
        var result: [Int: ResolvedAttachment] = [:]
        for attachment in text.attachments {
            switch attachment.content {
            case .image:
                continue
            case .emoji(let name, let fallback):
                switch emoji(name) {
                case .text(let string)?: result[attachment.id] = .text(string)
                case .systemImage(let symbol)?: result[attachment.id] = .symbol(symbol)
                case .image(let url)?:
                    if let image = loaded(url, for: attachment) { result[attachment.id] = Self.resolve(image, for: attachment, in: text) }
                    else { result[attachment.id] = .text(fallback.count > 3 ? "▫️" : fallback) }
                case nil: result[attachment.id] = .text(fallback.count > 3 ? "▫️" : fallback)
                }
            case .remoteImage(let url, _):
                if let image = loaded(url, for: attachment) {
                    result[attachment.id] = Self.resolve(image, for: attachment, in: text)
                }
            }
        }
        return result
    }

    private static func resolve(_ image: MarkdownImage, for attachment: CoreTextAttachment, in text: RichText) -> ResolvedAttachment {
        // Keep the image's aspect ratio: widen the attachment once its size is known.
        if case .remoteImage = attachment.content {
            let size = image.pixelSize
            let height = attachment.ascent + attachment.descent
            if size.height > 0 {
                text.setAttachmentWidth(min(height * size.width / size.height, height * 8), for: attachment.id)
            }
        }
        switch image.content {
        case .still(let still): return .image(still.cgImage)
        case .animated(let animation): return .animated(animation)
        }
    }

    private var pendingKey: [URL] {
        text.attachments.compactMap(url(for:)).sorted { $0.absoluteString < $1.absoluteString }
    }

    private func loadImages() async {
        let pending = text.attachments.compactMap { attachment -> (URL, CGFloat)? in
            guard let url = url(for: attachment), loaded(url, for: attachment) == nil else { return nil }
            return (url, maxPixelSize(attachment))
        }
        guard !pending.isEmpty else { return }
        await withTaskGroup(of: (URL, MarkdownImage?).self) { group in
            for (url, size) in pending {
                let loader = loader
                group.addTask { (url, try? await loader.loadImage(from: url, maxPixelSize: size)) }
            }
            for await (url, image) in group {
                if let image { images[url] = image }
            }
        }
    }
}

/// Link taps and link accessibility actions (only installed when the text has links).
private struct LinkInteraction: ViewModifier {
    let text: RichText
    let indent: CGFloat

    func body(content: Content) -> some View {
        if text.links.isEmpty {
            content
        } else {
            LinkInteractionBody(content: content, text: text, indent: indent)
        }
    }
}

private struct LinkInteractionBody<Content: View>: View {
    let content: Content
    let text: RichText
    let indent: CGFloat
    @Environment(\.openURL) private var openURL

    var body: some View {
        content
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                let point = CGPoint(x: location.x - indent, y: location.y)
                if let url = text.lastLayout?.link(at: point) { openURL(url) }
            }
            .accessibilityAddTraits(.isLink)
            .accessibilityActions {
                ForEach(text.links, id: \.self) { url in
                    Button("Open \(url.host() ?? url.absoluteString)") { openURL(url) }
                }
            }
    }
}
