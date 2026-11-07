import SwiftUI
import CoreText

/// Typeset lines of a text block for one width.
struct TextLayout: @unchecked Sendable {
    let lines: [TableLayout.Line]
    let size: CGSize
    let decorations: [TableLayout.Decoration]
    let attachments: [TableLayout.Attachment]
    let links: [TableLayout.Link]
    /// End of the last line (baseline origin + width), for the streaming cursor.
    let lastLineEnd: CGPoint
    let lastLineAscent: CGFloat

    func link(at point: CGPoint) -> URL? {
        links.first { $0.rect.insetBy(dx: -3, dy: -3).contains(point) }?.url
    }

    static let empty = TextLayout(lines: [], size: .zero, decorations: [], attachments: [], links: [],
                                  lastLineEnd: .zero, lastLineAscent: 0)
}

/// A text block prepared for CoreText rendering. Layouts are computed per width and memoized; they can
/// be precomputed off the main thread when the width is known ahead of time.
final class RichText: @unchecked Sendable {
    let string: NSAttributedString
    let attachments: [CoreTextAttachment]
    let plainText: String
    let lineSpacing: CGFloat
    let fontSize: CGFloat
    let links: [URL]
    private let minimumAscent: CGFloat
    private let minimumDescent: CGFloat
    private let isRightToLeft: Bool

    private let lock = NSLock()
    private var typesetter: CTTypesetter?
    private var layouts: [(width: CGFloat, layout: TextLayout)] = []
    private var natural: TextLayout?
    private(set) var lastLayout: TextLayout?

    init(string: NSAttributedString, attachments: [CoreTextAttachment], plainText: String, lineSpacing: CGFloat,
         baseFont: PlatformFont) {
        self.string = string
        self.attachments = attachments
        self.plainText = plainText
        self.lineSpacing = lineSpacing
        fontSize = baseFont.pointSize
        minimumAscent = ceil(baseFont.ascender)
        minimumDescent = ceil(-baseFont.descender)
        var links: [URL] = []
        string.enumerateAttribute(CoreTextKeys.link, in: NSRange(location: 0, length: string.length)) { value, _, _ in
            if let url = value as? URL, links.last != url { links.append(url) }
        }
        self.links = links
        isRightToLeft = Self.detectRightToLeft(plainText)
    }

    var minimumLineHeight: CGFloat { minimumAscent + minimumDescent }

    /// Layout at `width`, memoized (a few recent widths are kept).
    func layout(width: CGFloat) -> TextLayout {
        let width = max(1, width.rounded(toPlaces: 2))
        lock.lock()
        if let hit = layouts.first(where: { $0.width == width }) {
            lastLayout = hit.layout
            lock.unlock()
            return hit.layout
        }
        let typesetter = self.typesetter ?? CTTypesetterCreateWithAttributedString(string)
        self.typesetter = typesetter
        lock.unlock()

        let layout = makeLayout(typesetter: typesetter, width: width)
        lock.lock()
        layouts.append((width, layout))
        if layouts.count > 3 { layouts.removeFirst() }
        lastLayout = layout
        lock.unlock()
        return layout
    }

    /// Unconstrained layout (longest line), for ideal-size queries.
    func naturalLayout() -> TextLayout {
        lock.lock()
        if let natural { lock.unlock(); return natural }
        let typesetter = self.typesetter ?? CTTypesetterCreateWithAttributedString(string)
        self.typesetter = typesetter
        lock.unlock()
        let layout = makeLayout(typesetter: typesetter, width: 100_000)
        let trimmed = TextLayout(lines: layout.lines, size: CGSize(width: ceil(layout.lines.reduce(0) { max($0, $1.width) }), height: layout.size.height),
                                 decorations: layout.decorations, attachments: layout.attachments, links: layout.links,
                                 lastLineEnd: layout.lastLineEnd, lastLineAscent: layout.lastLineAscent)
        lock.lock()
        natural = trimmed
        lock.unlock()
        return trimmed
    }

    /// Updates an attachment's width (e.g. an inline image whose aspect ratio became known) and drops
    /// memoized layouts. Returns `true` if anything changed.
    @discardableResult
    func setAttachmentWidth(_ width: CGFloat, for id: Int) -> Bool {
        guard id < attachments.count, attachments[id].setWidth(width) else { return false }
        lock.lock()
        typesetter = nil
        layouts.removeAll()
        natural = nil
        lock.unlock()
        return true
    }

    private func makeLayout(typesetter: CTTypesetter, width: CGFloat) -> TextLayout {
        var lines: [TableLayout.Line] = []
        var decorations: [TableLayout.Decoration] = []
        var attachments: [TableLayout.Attachment] = []
        var links: [TableLayout.Link] = []
        let length = string.length
        var start = 0
        var y: CGFloat = 0
        var lastEnd = CGPoint.zero
        var lastAscent: CGFloat = minimumAscent
        while start < length {
            var count = CTTypesetterSuggestLineBreak(typesetter, start, Double(width))
            if count <= 0 { count = CTTypesetterSuggestClusterBreak(typesetter, start, Double(width)) }
            if count <= 0 { count = length - start }
            let line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count))
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            let typographic = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            let lineWidth = typographic - CGFloat(CTLineGetTrailingWhitespaceWidth(line))
            ascent = max(ceil(ascent), minimumAscent)
            descent = max(ceil(descent), minimumDescent)
            if !lines.isEmpty { y += lineSpacing }
            let x: CGFloat = isRightToLeft ? max(0, width - lineWidth) : 0
            let baseline = CGPoint(x: x, y: y + ascent)
            lines.append(TableLayout.Line(line: line, origin: baseline, width: lineWidth))
            TableLayoutEngine.collectRunDecorations(line, baseline: baseline, ascent: ascent, descent: descent,
                                                    decorations: &decorations, attachments: &attachments, links: &links)
            y += ascent + descent
            lastEnd = CGPoint(x: x + lineWidth, y: baseline.y)
            lastAscent = ascent
            start += count
        }
        if lines.isEmpty { y = minimumLineHeight }
        return TextLayout(lines: lines, size: CGSize(width: width, height: ceil(y)), decorations: decorations,
                          attachments: attachments, links: links, lastLineEnd: lastEnd, lastLineAscent: lastAscent)
    }

    private static func detectRightToLeft(_ text: String) -> Bool {
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            let v = scalar.value
            return (0x0590...0x08FF).contains(v) || (0xFB1D...0xFDFF).contains(v) || (0xFE70...0xFEFF).contains(v)
        }
        return false
    }
}
