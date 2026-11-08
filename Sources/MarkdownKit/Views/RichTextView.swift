import SwiftUI
import CoreText
import Synchronization

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

    private struct CenteredKey: Hashable {
        let string: String
        let height: CGFloat
    }

    /// Typeset emoji lines. Creating them involves a font fallback lookup, too slow to repeat on every draw.
    private static let centeredLines = Mutex<[CenteredKey: (line: CTLine, width: CGFloat)]>([:])

    /// Draws a short string (emoji) centered horizontally in `rect`, baseline at `baselineRatio` of its height.
    static func drawCentered(_ string: String, in rect: CGRect, baselineRatio: CGFloat, context cg: CGContext) {
        let key = CenteredKey(string: string, height: rect.height)
        let typeset = centeredLines.withLock { cache -> (line: CTLine, width: CGFloat) in
            if let hit = cache[key] { return hit }
            let font = PlatformFont.systemFont(ofSize: rect.height * 0.8)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [CoreTextKeys.font: font]))
            let entry = (line, CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
            if cache.count > 512 { cache.removeAll() }
            cache[key] = entry
            return entry
        }
        cg.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        cg.textPosition = CGPoint(x: rect.midX - typeset.width / 2, y: rect.minY + rect.height * baselineRatio)
        CTLineDraw(typeset.line, cg)
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

/// Sizes a single `Canvas` child from a ``RichStack`` layout for the proposed width.
struct RichTextLayout: Layout {
    let stack: RichStack
    /// Changes when attachment sizes change, so SwiftUI re-measures.
    var version: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let width = proposal.width, width.isFinite else { return stack.naturalSize() }
        return CGSize(width: width, height: stack.place(width: width).height)
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

/// Text typeset with CoreText (off the main thread when the width is known in advance) and drawn in a
/// `Canvas`. About 8× cheaper to lay out than SwiftUI `Text` for rich paragraphs. A whole list or quote
/// can be drawn by one view (see ``RichStack``).
struct RichTextView: View {
    let stack: RichStack
    let theme: ResolvedTheme
    var showsCursor = false

    init(stack: RichStack, theme: ResolvedTheme, showsCursor: Bool = false) {
        self.stack = stack
        self.theme = theme
        self.showsCursor = showsCursor
    }

    init(text: RichText, theme: ResolvedTheme, showsCursor: Bool = false, marker: ListMarker? = nil,
         markerLine: MarkerLine? = nil, indent: CGFloat = 0, markerWidth: CGFloat = 0) {
        self.init(stack: RichStack(text: text, marker: marker, markerLine: markerLine, indent: indent, markerWidth: markerWidth),
                  theme: theme, showsCursor: showsCursor)
    }

    var body: some View {
        if stack.needsRuntimeAttachments {
            AttachmentRichTextView(stack: stack, theme: theme, showsCursor: showsCursor)
        } else {
            // Lightweight path: no state, no environment reads, no tasks.
            Self.core(stack: stack, theme: theme, resolved: [:], showsCursor: showsCursor, playback: .none)
        }
    }

    /// Which attachments a canvas pass draws.
    enum Pass {
        /// Everything, animated images frozen on their first frame.
        case still
        /// Text and still attachments; animated images are drawn by an overlay.
        case base
        /// Only the animated images, at a point in time.
        case animations(TimeInterval)
    }

    /// How animated images play.
    enum Playback {
        /// Frozen on the first frame.
        case none
        /// Core Animation keyframe animations (no per-frame main-thread work).
        case layers([AnimatedLayerView.Item])
        /// A `TimelineView` overlay redrawn at this interval (animations too large to keep in memory).
        case timeline(TimeInterval)
    }

    @ViewBuilder
    static func core(stack: RichStack, theme: ResolvedTheme, resolved: [Int: ResolvedAttachment], showsCursor: Bool,
                     playback: Playback) -> some View {
        let cursorColor = showsCursor ? theme.secondaryColor.cgColor : nil
        let textColor = theme.textColor
        let pass: Pass = if case .none = playback { .still } else { .base }
        RichTextLayout(stack: stack, version: stack.attachmentVersion) {
            canvas(stack: stack, resolved: resolved, pass: pass, cursorColor: cursorColor, textColor: textColor)
        }
        .overlay {
            switch playback {
            case .none:
                EmptyView()
            case .layers(let items):
                AnimatedLayerView(items: items)
            case .timeline(let interval):
                // The text itself is never redrawn per frame, only this overlay.
                TimelineView(.animation(minimumInterval: interval)) { context in
                    canvas(stack: stack, resolved: resolved, pass: .animations(context.date.timeIntervalSinceReferenceDate),
                           cursorColor: nil, textColor: textColor)
                }
                .accessibilityHidden(true)
                .allowsHitTesting(false)
            }
        }
        // Expose text baselines so surrounding views can align with the first and last lines.
        .alignmentGuide(.firstTextBaseline) { dimensions in
            let placement = stack.place(width: dimensions.width).placements.first
            return placement.flatMap { p in p.layout.lines.first.map { p.origin.y + $0.origin.y } } ?? dimensions[.bottom]
        }
        .alignmentGuide(.lastTextBaseline) { dimensions in
            let placement = stack.place(width: dimensions.width).placements.last
            return placement.flatMap { p in p.layout.lines.last.map { p.origin.y + $0.origin.y } } ?? dimensions[.bottom]
        }
        .accessibilityElement()
        .accessibilityLabel(stack.accessibilityText)
        .modifier(LinkInteraction(stack: stack))
    }

    private static func canvas(stack: RichStack, resolved: [Int: ResolvedAttachment], pass: Pass,
                               cursorColor: CGColor?, textColor: Color.Resolved) -> some View {
        Canvas(rendersAsynchronously: false) { context, size in
            draw(stack: stack, resolved: resolved, pass: pass, cursorColor: cursorColor, textColor: textColor,
                 context: &context, size: size)
        }
    }

    private static func draw(stack: RichStack, resolved: [Int: ResolvedAttachment], pass: Pass,
                             cursorColor: CGColor?, textColor: Color.Resolved, context: inout GraphicsContext, size: CGSize) {
        let placements = stack.place(width: size.width).placements
        if case .animations(let time) = pass {
            for (index, placement) in placements.enumerated() {
                for item in placement.layout.attachments {
                    guard case .animated(let animation)? = resolved[RichStack.key(entry: index, attachment: item.attachment.id)] else { continue }
                    context.draw(Image(decorative: animation.frame(at: time), scale: 1),
                                 in: item.rect.offsetBy(dx: placement.origin.x, dy: placement.origin.y))
                }
            }
            return
        }
        if !stack.bars.isEmpty {
            context.withCGContext { cg in
                for bar in stack.bars {
                    let first = placements[bar.first], last = placements[bar.last]
                    let top = first.origin.y - bar.inset
                    let bottom = last.origin.y + max(last.layout.size.height, stack.entries[bar.last].text.minimumLineHeight) + bar.inset
                    if let background = bar.background {
                        cg.setFillColor(background)
                        cg.fill(CGRect(x: bar.x, y: top, width: size.width - bar.x, height: bottom - top))
                    }
                    cg.setFillColor(bar.color)
                    cg.fill(CGRect(x: bar.x, y: top, width: bar.width, height: bottom - top))
                }
            }
        }
        for (index, placement) in placements.enumerated() {
            let entry = stack.entries[index]
            let layout = placement.layout
            if let marker = entry.marker, let firstBaseline = layout.lines.first?.origin.y {
                drawMarker(marker, baseline: placement.origin.y + firstBaseline, context: &context)
            }
            var local = context
            local.translateBy(x: placement.origin.x, y: placement.origin.y)
            let isLast = index == placements.count - 1
            drawText(layout: layout, entry: index, text: entry.text, resolved: resolved, pass: pass,
                     cursorColor: isLast ? cursorColor : nil, textColor: textColor, context: &local)
        }
    }

    private static func drawMarker(_ marker: RichStack.Marker, baseline: CGFloat, context: inout GraphicsContext) {
        if let line = marker.line {
            context.withCGContext { cg in
                cg.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
                cg.textPosition = CGPoint(x: marker.trailing - line.width, y: baseline)
                CTLineDraw(line.line, cg)
            }
            return
        }
        let markerText: Text = switch marker.kind {
        case .text(let string): Text(string)
        case .checkbox(let checked, let size, let color):
            Text(Image(systemName: checked ? "checkmark.square.fill" : "square"))
                .font(.system(size: size * 0.95))
                .foregroundStyle(Color(color))
        }
        let resolvedMarker = context.resolve(markerText)
        let markerSize = resolvedMarker.measure(in: CGSize(width: 1000, height: 1000))
        let markerBaseline = resolvedMarker.firstBaseline(in: markerSize)
        context.draw(resolvedMarker, in: CGRect(x: marker.trailing - markerSize.width, y: baseline - markerBaseline,
                                                width: markerSize.width, height: markerSize.height))
    }

    private static func drawText(layout: TextLayout, entry: Int, text: RichText, resolved: [Int: ResolvedAttachment],
                                 pass: Pass, cursorColor: CGColor?, textColor: Color.Resolved,
                                 context: inout GraphicsContext) {
        context.withCGContext { cg in
            CoreTextDrawing.drawText(lines: layout.lines, decorations: layout.decorations, in: cg)
            for item in layout.attachments {
                if case .text(let string)? = resolved[RichStack.key(entry: entry, attachment: item.attachment.id)] {
                    CoreTextDrawing.drawCentered(string, in: item.rect, baselineRatio: 0.8, context: cg)
                }
            }
            if let cursorColor {
                let diameter = text.fontSize * 0.55
                let center = CGPoint(x: layout.lastLineEnd.x + diameter, y: layout.lastLineEnd.y - layout.lastLineAscent * 0.35)
                cg.setFillColor(cursorColor)
                cg.fillEllipse(in: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter))
            }
        }
        // Images and symbols are drawn natively by SwiftUI (GPU textures, cached per image) rather than
        // through Core Graphics.
        for item in layout.attachments {
            switch item.attachment.content {
            case .image(let image, _):
                context.draw(Image(decorative: image.cgImage, scale: image.scale), in: item.rect)
            case .emoji, .remoteImage:
                switch resolved[RichStack.key(entry: entry, attachment: item.attachment.id)] {
                case .image(let image)?:
                    context.draw(Image(decorative: image, scale: 1), in: item.rect)
                case .animated(let animation)?:
                    if case .still = pass { context.draw(Image(decorative: animation.frame(index: 0), scale: 1), in: item.rect) }
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
}

/// Rich text whose custom emoji or images are resolved and loaded at display time.
private struct AttachmentRichTextView: View {
    let stack: RichStack
    let theme: ResolvedTheme
    var showsCursor = false

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
        let animations = animatedItems(resolved)
        let canPlay = !animations.isEmpty && animates && !reduceMotion
        // Core Animation plays the frames when they all fit in memory; otherwise a TimelineView overlay,
        // which needs visibility tracking to pause off screen.
        let usesLayers = canPlay && animations.allSatisfy { $0.animation.allFrames != nil }
        let playback: RichTextView.Playback = if usesLayers {
            .layers(animations)
        } else if canPlay, isVisible, scenePhase != .background {
            .timeline(max(animations.map(\.animation.minimumDelay).min() ?? 0.1, 1.0 / 60))
        } else {
            .none
        }
        let pending = pendingKey
        RichTextView.core(stack: stack, theme: theme, resolved: resolved, showsCursor: showsCursor, playback: playback)
            // Geometry tracking costs work on every scrolled frame: only for timeline-driven animations.
            .modifier(VisibilityTracker(isActive: canPlay && !usesLayers, isVisible: $isVisible))
            .modifier(LoadTask(urls: pending, load: loadImages))
    }

    private func animatedItems(_ resolved: [Int: ResolvedAttachment]) -> [AnimatedLayerView.Item] {
        var items: [AnimatedLayerView.Item] = []
        let stack = stack
        for (index, entry) in stack.entries.enumerated() {
            for attachment in entry.text.attachments {
                guard case .animated(let animation)? = resolved[RichStack.key(entry: index, attachment: attachment.id)] else { continue }
                let id = attachment.id
                items.append(AnimatedLayerView.Item(animation: animation) { size in
                    let placement = stack.place(width: size.width).placements[index]
                    guard let item = placement.layout.attachments.first(where: { $0.attachment.id == id }) else { return .zero }
                    return item.rect.offsetBy(dx: placement.origin.x, dy: placement.origin.y)
                })
            }
        }
        return items
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
        for (index, entry) in stack.entries.enumerated() {
            let text = entry.text
            for attachment in text.attachments {
                let key = RichStack.key(entry: index, attachment: attachment.id)
                switch attachment.content {
                case .image:
                    continue
                case .emoji(let name, let fallback):
                    switch emoji(name) {
                    case .text(let string)?: result[key] = .text(string)
                    case .systemImage(let symbol)?: result[key] = .symbol(symbol)
                    case .image(let url)?:
                        if let image = loaded(url, for: attachment) { result[key] = Self.resolve(image, for: attachment, in: text) }
                        else { result[key] = .text(fallback.count > 3 ? "▫️" : fallback) }
                    case nil: result[key] = .text(fallback.count > 3 ? "▫️" : fallback)
                    }
                case .remoteImage(let url, _):
                    if let image = loaded(url, for: attachment) {
                        result[key] = Self.resolve(image, for: attachment, in: text)
                    }
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

    private var allAttachments: [CoreTextAttachment] { stack.entries.flatMap(\.text.attachments) }

    /// URLs still to load. Empty (no task attached) when everything is already in memory.
    private var pendingKey: [URL] {
        var seen = Set<URL>()
        return allAttachments.compactMap { attachment -> URL? in
            guard let url = url(for: attachment), loaded(url, for: attachment) == nil, seen.insert(url).inserted else { return nil }
            return url
        }.sorted { $0.absoluteString < $1.absoluteString }
    }

    private func loadImages() async {
        var seen = Set<URL>()
        let pending = allAttachments.compactMap { attachment -> (URL, CGFloat)? in
            guard let url = url(for: attachment), loaded(url, for: attachment) == nil, seen.insert(url).inserted else { return nil }
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
    let stack: RichStack

    func body(content: Content) -> some View {
        if stack.hasLinks {
            LinkInteractionBody(content: content, stack: stack)
        } else {
            content
        }
    }
}

private struct LinkInteractionBody<Content: View>: View {
    let content: Content
    let stack: RichStack
    @Environment(\.openURL) private var openURL

    var body: some View {
        content
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                if let url = stack.link(at: location) { openURL(url) }
            }
            .accessibilityAddTraits(.isLink)
            .accessibilityAction(named: Text("Open link")) {
                if let url = stack.firstLink { openURL(url) }
            }
    }
}

/// Tracks on-screen visibility (to pause animations) only when needed.
private struct VisibilityTracker: ViewModifier {
    let isActive: Bool
    @Binding var isVisible: Bool

    func body(content: Content) -> some View {
        if isActive {
            content.onScrollVisibilityChange(threshold: 0.01) { isVisible = $0 }
        } else {
            content
        }
    }
}

/// Starts image loading only when something actually needs loading.
private struct LoadTask: ViewModifier {
    let urls: [URL]
    let load: () async -> Void

    func body(content: Content) -> some View {
        if urls.isEmpty {
            content
        } else {
            content.task(id: urls) { await load() }
        }
    }
}
