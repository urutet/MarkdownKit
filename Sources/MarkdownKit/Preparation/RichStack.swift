import SwiftUI
import CoreText

/// A list marker rendered with CoreText (bullet or number), prepared off the main thread.
final class MarkerLine: @unchecked Sendable {
    let line: CTLine
    let width: CGFloat
    let string: String

    init(string: String, font: PlatformFont, color: CGColor) {
        let ctFont = font as CTFont
        let descriptor = CTFontDescriptorCreateCopyWithFeature(CTFontCopyFontDescriptor(ctFont),
                                                               NSNumber(value: kNumberSpacingType),
                                                               NSNumber(value: kMonospacedNumbersSelector))
        let monospaced = CTFontCreateWithFontDescriptor(descriptor, CTFontGetSize(ctFont), nil)
        let attributed = NSAttributedString(string: string, attributes: [CoreTextKeys.font: monospaced,
                                                                         CoreTextKeys.foreground: color])
        line = CTLineCreateWithAttributedString(attributed)
        width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        self.string = string
    }
}

/// Text pieces stacked vertically and drawn by one view: a paragraph, or a whole list or block quote.
///
/// Every SwiftUI `Canvas` is its own layer that has to be rendered when it scrolls into view, so drawing
/// a list or quote in one canvas instead of one per item cuts the per-row rendering cost.
struct RichStack: @unchecked Sendable {
    struct Marker {
        let kind: ListMarker
        let line: MarkerLine?
        /// X of the marker's trailing edge.
        let trailing: CGFloat
    }

    struct Entry {
        let text: RichText
        /// Leading offset of the text.
        let x: CGFloat
        var spacingBefore: CGFloat
        var spacingAfter: CGFloat = 0
        var marker: Marker?
    }

    /// A block quote's bar (and optional background) spanning entries `first...last`.
    struct Bar {
        let first: Int
        let last: Int
        let x: CGFloat
        let width: CGFloat
        let color: CGColor
        let background: CGColor?
        /// Vertical padding between the background edge and the text.
        let inset: CGFloat
    }

    struct Placement {
        let origin: CGPoint
        let layout: TextLayout
    }

    var entries: [Entry]
    var bars: [Bar] = []

    init(entries: [Entry], bars: [Bar] = []) {
        self.entries = entries
        self.bars = bars
    }

    /// A single paragraph, optionally with a list marker in a hanging indent.
    init(text: RichText, marker: ListMarker? = nil, markerLine: MarkerLine? = nil, indent: CGFloat = 0, markerWidth: CGFloat = 0) {
        entries = [Entry(text: text, x: indent, spacingBefore: 0,
                         marker: marker.map { Marker(kind: $0, line: markerLine, trailing: markerWidth) })]
    }

    var isSingle: Bool { entries.count == 1 && bars.isEmpty }

    /// Sum of attachment widths, changes when an image's aspect ratio becomes known.
    var attachmentVersion: CGFloat {
        entries.reduce(0) { sum, entry in entry.text.attachments.reduce(sum) { $0 + $1.width } }
    }

    var needsRuntimeAttachments: Bool {
        entries.contains { entry in
            entry.text.attachments.contains { if case .image = $0.content { return false }; return true }
        }
    }

    var hasLinks: Bool { entries.contains { !$0.text.links.isEmpty } }

    var firstLink: URL? { entries.lazy.compactMap(\.text.links.first).first }

    var accessibilityText: String {
        if isSingle { return entries[0].text.plainText }
        return entries.map { entry in
            switch entry.marker?.kind {
            case .checkbox(let checked, _, _)?: "\(checked ? "Completed" : "Not completed"), \(entry.text.plainText)"
            case .text?: "\(entry.marker?.line?.string ?? "•") \(entry.text.plainText)"
            case nil: entry.text.plainText
            }
        }.joined(separator: "\n")
    }

    /// Key of an attachment across all entries.
    static func key(entry: Int, attachment: Int) -> Int { entry << 20 | attachment }

    /// Lays out every entry for `width`. Entry layouts are memoized by ``RichText``.
    func place(width: CGFloat) -> (placements: [Placement], height: CGFloat) {
        place { $0.text.layout(width: max(1, width - $0.x)) }
    }

    /// Lays out using each entry's most recent layout (what was last drawn), for hit testing.
    func placeUsingLastLayouts() -> [Placement] {
        place { $0.text.lastLayout ?? .empty }.placements
    }

    func naturalSize() -> CGSize {
        var width: CGFloat = 0
        let height = place { entry in
            let layout = entry.text.naturalLayout()
            width = max(width, entry.x + layout.size.width)
            return layout
        }.height
        return CGSize(width: width, height: height)
    }

    private func place(_ layout: (Entry) -> TextLayout) -> (placements: [Placement], height: CGFloat) {
        var placements: [Placement] = []
        placements.reserveCapacity(entries.count)
        var y: CGFloat = 0
        for entry in entries {
            y += entry.spacingBefore
            let entryLayout = layout(entry)
            placements.append(Placement(origin: CGPoint(x: entry.x, y: y), layout: entryLayout))
            y += max(entryLayout.size.height, entry.text.minimumLineHeight) + entry.spacingAfter
        }
        return (placements, ceil(y))
    }

    func link(at point: CGPoint) -> URL? {
        for placement in placeUsingLastLayouts() {
            let local = CGPoint(x: point.x - placement.origin.x, y: point.y - placement.origin.y)
            guard local.y >= -4, local.y <= placement.layout.size.height + 4 else { continue }
            if let url = placement.layout.link(at: local) { return url }
        }
        return nil
    }
}

extension RichStack {
    /// Flattens list or quote content into one stack. Returns `nil` when the content contains blocks
    /// that need their own views (code, tables, images, headings…).
    static func flatten(_ content: PreparedContent, theme: ResolvedTheme) -> RichStack? {
        var builder = Builder(theme: theme)
        guard builder.block(content, x: 0), !builder.entries.isEmpty else { return nil }
        return RichStack(entries: builder.entries, bars: builder.bars)
    }

    /// Mirrors the spacing of the view-per-block rendering (`BlockStack`, `ListBlockView`,
    /// `BlockquoteView`).
    private struct Builder {
        let theme: ResolvedTheme
        var entries: [Entry] = []
        var bars: [Bar] = []
        /// Space to put before the next entry.
        var gap: CGFloat = 0

        init(theme: ResolvedTheme) { self.theme = theme }

        mutating func add(_ text: RichText, x: CGFloat, marker: Marker? = nil) {
            entries.append(Entry(text: text, x: x, spacingBefore: gap, marker: marker))
            gap = 0
        }

        mutating func blocks(_ blocks: [PreparedBlock], x: CGFloat, spacing: CGFloat) -> Bool {
            for (index, block) in blocks.enumerated() {
                if index > 0 { gap += spacing + block.spacingBefore }
                guard self.block(block.content, x: x) else { return false }
            }
            return true
        }

        mutating func block(_ content: PreparedContent, x: CGFloat) -> Bool {
            switch content {
            case .text(let text, .paragraph), .text(let text, .html):
                guard let rich = text.rich else { return false }
                add(rich, x: x)
                return true
            case .list(let list):
                return self.list(list, x: x)
            case .blockquote(let blocks, _):
                return quote(blocks, x: x)
            default:
                return false
            }
        }

        mutating func list(_ list: PreparedList, x: CGFloat) -> Bool {
            let indent = list.markerWidth + list.markerSpacing
            for (index, item) in list.items.enumerated() {
                if index > 0 { gap += list.itemSpacing }
                guard let first = item.blocks.first, case .text(let text, .paragraph) = first.content,
                      let rich = text.rich else { return false }
                add(rich, x: x + indent, marker: Marker(kind: item.marker, line: item.markerLine, trailing: x + list.markerWidth))
                for block in item.blocks.dropFirst() {
                    gap += list.itemSpacing + block.spacingBefore
                    guard self.block(block.content, x: x + indent) else { return false }
                }
            }
            return true
        }

        mutating func quote(_ blocks: [PreparedBlock], x: CGFloat) -> Bool {
            let style = theme.theme.blockquote
            let barWidth = theme.length(style.barWidth)
            let inset = theme.quoteBackground == nil ? 0 : theme.length(.em(0.4))
            gap += inset
            let first = entries.count
            guard self.blocks(blocks, x: x + barWidth + theme.length(style.indent), spacing: theme.length(theme.theme.blockSpacing)),
                  entries.count > first else { return false }
            entries[entries.count - 1].spacingAfter += inset
            bars.append(Bar(first: first, last: entries.count - 1, x: x, width: barWidth, color: theme.quoteBarColor.cgColor,
                            background: theme.quoteBackground?.cgColor, inset: inset))
            return true
        }
    }
}
