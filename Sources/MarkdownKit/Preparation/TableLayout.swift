import SwiftUI
import CoreText

/// Precomputed layout of a table: column widths, row heights and typeset lines for every cell.
///
/// Computed off the main thread with CoreText; drawing only replays the lines, so SwiftUI never has to
/// measure hundreds of `Text` views.
struct TableLayout: @unchecked Sendable {
    struct Line {
        let line: CTLine
        /// Baseline origin relative to the top-left corner.
        let origin: CGPoint
        var width: CGFloat = 0
    }

    struct Decoration {
        enum Kind { case background, strikethrough }
        let kind: Kind
        let rect: CGRect
        let color: CGColor
    }

    struct Attachment {
        let attachment: CoreTextAttachment
        let rect: CGRect
    }

    struct Link {
        let rect: CGRect
        let url: URL
    }

    struct Cell {
        let row: Int
        let column: Int
        let lines: [Line]
        let decorations: [Decoration]
        let attachments: [Attachment]
    }

    let columnOffsets: [CGFloat]   // count = columns + 1
    let rowOffsets: [CGFloat]      // count = rows + 1 (row 0 is the header)
    let cells: [[Cell]]            // [row][column]
    let links: [Link]
    let plainRows: [[String]]

    // Style.
    let headerBackground: CGColor?
    let stripeBackground: CGColor?
    let borderColor: CGColor
    let borderWidth: CGFloat
    let cornerRadius: CGFloat

    var columnCount: Int { columnOffsets.count - 1 }
    var rowCount: Int { rowOffsets.count - 1 }
    var size: CGSize { CGSize(width: columnOffsets.last ?? 0, height: rowOffsets.last ?? 0) }

    /// Tab-separated text, used for copying.
    var tsv: String {
        plainRows.map { $0.joined(separator: "\t") }.joined(separator: "\n")
    }

    /// GitHub-flavored Markdown source, used for copying.
    var markdown: String {
        guard let header = plainRows.first else { return "" }
        func row(_ cells: [String]) -> String {
            "| " + cells.map { $0.replacingOccurrences(of: "|", with: "\\|") }.joined(separator: " | ") + " |"
        }
        var lines = [row(header), "|" + Array(repeating: " --- |", count: header.count).joined()]
        lines += plainRows.dropFirst().map(row)
        return lines.joined(separator: "\n")
    }

    func link(at point: CGPoint) -> URL? {
        links.first { $0.rect.insetBy(dx: -4, dy: -4).contains(point) }?.url
    }

    /// Column ranges whose combined width is about `maxWidth`, for tiled rendering.
    func columnTiles(maxWidth: CGFloat) -> [Range<Int>] {
        var tiles: [Range<Int>] = []
        var start = 0
        while start < columnCount {
            var end = start + 1
            while end < columnCount, columnOffsets[end + 1] - columnOffsets[start] <= maxWidth { end += 1 }
            tiles.append(start..<end)
            start = end
        }
        return tiles
    }

    /// Row ranges whose combined height is about `maxHeight`, for tiled rendering.
    func rowTiles(maxHeight: CGFloat) -> [Range<Int>] {
        var tiles: [Range<Int>] = []
        var start = 0
        while start < rowCount {
            var end = start + 1
            while end < rowCount, rowOffsets[end + 1] - rowOffsets[start] <= maxHeight { end += 1 }
            tiles.append(start..<end)
            start = end
        }
        return tiles
    }
}

/// Measures and line-breaks table cells with CoreText. Large tables are processed in parallel.
struct TableLayoutEngine {
    let theme: ResolvedTheme
    let math: (any MathRendering)?
    let textColor: Color.Resolved

    typealias BrokenLine = (CTLine, CGFloat, CGFloat, CGFloat) // line, ascent, descent, width

    /// A measured cell, cached across layouts (streaming tables re-layout on every update, but only
    /// new or changed cells need CoreText work). Immutable except for the line-break memo.
    final class Measured: @unchecked Sendable {
        let string: NSAttributedString
        let typesetter: CTTypesetter?
        let naturalWidth: CGFloat
        let plain: String
        private let lock = NSLock()
        private var memo: (width: CGFloat, lines: [BrokenLine])?

        init(string: NSAttributedString, typesetter: CTTypesetter?, naturalWidth: CGFloat, plain: String) {
            self.string = string
            self.typesetter = typesetter
            self.naturalWidth = naturalWidth
            self.plain = plain
        }

        func lines(width: CGFloat) -> [BrokenLine] {
            lock.lock()
            if let memo, memo.width == width { lock.unlock(); return memo.lines }
            lock.unlock()
            let lines = TableLayoutEngine.breakLines(self, width: width)
            lock.lock()
            memo = (width, lines)
            lock.unlock()
            return lines
        }
    }

    private static let cellCache = SendableCache<Int, Measured>(totalCostLimit: 24 << 20)

    static func removeCachedCells() { cellCache.removeAll() }

    func layout(_ table: MarkdownTable) -> TableLayout {
        let style = theme.theme.table
        let columns = max(table.columnCount, 1)
        let allRows: [[[MarkdownInline]]] = [table.header] + table.rows
        let rowCount = allRows.count
        let horizontalPadding = theme.length(style.horizontalPadding, fontScale: style.font.scale)
        let verticalPadding = theme.length(style.verticalPadding, fontScale: style.font.scale)
        let maxContentWidth = theme.length(style.maxColumnWidth, fontScale: style.font.scale)
        let minContentWidth = theme.length(style.minColumnWidth, fontScale: style.font.scale)
        let color = textColor.cgColor

        // Pass 1: attributed strings, typesetters and natural widths (parallel by row).
        var measured = [[Measured]](repeating: [], count: rowCount)
        Self.parallel(rowCount, cellCount: rowCount * columns) { rowRange in
            var builder = CoreTextInlineBuilder(theme: theme, math: math)
            var result: [(Int, [Measured])] = []
            for row in rowRange {
                let cells = allRows[row]
                let cellStyle = CoreTextInlineBuilder.Style(font: row == 0 ? style.headerFont : style.font, color: color)
                var rowMeasured: [Measured] = []
                rowMeasured.reserveCapacity(columns)
                for column in 0..<columns {
                    let inlines = column < cells.count ? cells[column] : []
                    var hasher = Hasher()
                    hasher.combine(inlines)
                    hasher.combine(row == 0)
                    hasher.combine(theme.fingerprint)
                    hasher.combine(textColor)
                    let key = hasher.finalize()
                    if let cached = Self.cellCache[key] {
                        rowMeasured.append(cached)
                        continue
                    }
                    let string = builder.build(inlines, style: cellStyle)
                    let cell = Self.measure(string, plain: inlines.plainText)
                    Self.cellCache.set(cell, for: key, cost: 256 + string.length * 16)
                    rowMeasured.append(cell)
                }
                result.append((row, rowMeasured))
            }
            return result
        } merge: { results in
            for (row, value) in results { measured[row] = value }
        }

        // Pass 2: column widths.
        var contentWidths = [CGFloat](repeating: minContentWidth, count: columns)
        for row in measured {
            for (column, cell) in row.enumerated() {
                contentWidths[column] = max(contentWidths[column], min(cell.naturalWidth, maxContentWidth))
            }
        }
        contentWidths = contentWidths.map { ceil($0) }
        var columnOffsets = [CGFloat](repeating: 0, count: columns + 1)
        for column in 0..<columns {
            columnOffsets[column + 1] = columnOffsets[column] + contentWidths[column] + 2 * horizontalPadding
        }

        // Pass 3: line breaking (parallel by row).
        struct Broken {
            var lines: [(CTLine, CGFloat, CGFloat, CGFloat)]  // line, ascent, descent, width
            var height: CGFloat
        }
        var broken = [[Broken]](repeating: [], count: rowCount)
        Self.parallel(rowCount, cellCount: rowCount * columns) { rowRange in
            var result: [(Int, [Broken])] = []
            for row in rowRange {
                var rowBroken: [Broken] = []
                for column in 0..<columns {
                    let cell = measured[row][column]
                    let lines = cell.lines(width: contentWidths[column])
                    let height = lines.reduce(0) { $0 + $1.1 + $1.2 + Self.lineGap(for: $1) }
                    rowBroken.append(Broken(lines: lines, height: height))
                }
                result.append((row, rowBroken))
            }
            return result
        } merge: { results in
            for (row, value) in results { broken[row] = value }
        }

        // Pass 4: row heights and positions.
        let minimumLineHeight = theme.size(style.font) * 1.2
        var rowOffsets = [CGFloat](repeating: 0, count: rowCount + 1)
        for row in 0..<rowCount {
            let content = max(broken[row].map(\.height).max() ?? 0, minimumLineHeight)
            rowOffsets[row + 1] = rowOffsets[row] + ceil(content + 2 * verticalPadding)
        }

        var cells: [[TableLayout.Cell]] = []
        var links: [TableLayout.Link] = []
        cells.reserveCapacity(rowCount)
        for row in 0..<rowCount {
            var rowCells: [TableLayout.Cell] = []
            rowCells.reserveCapacity(columns)
            for column in 0..<columns {
                let alignment = column < table.alignments.count ? table.alignments[column] : .none
                let cellBroken = broken[row][column]
                let originX = columnOffsets[column] + horizontalPadding
                var y = rowOffsets[row] + verticalPadding
                // Vertically center the content within the row.
                let rowContentHeight = rowOffsets[row + 1] - rowOffsets[row] - 2 * verticalPadding
                y += max(0, (rowContentHeight - cellBroken.height) / 2)
                var lines: [TableLayout.Line] = []
                var decorations: [TableLayout.Decoration] = []
                var attachments: [TableLayout.Attachment] = []
                for (line, ascent, descent, width) in cellBroken.lines {
                    let x: CGFloat = switch alignment {
                    case .center: originX + (contentWidths[column] - width) / 2
                    case .right: originX + contentWidths[column] - width
                    case .left, .none: originX
                    }
                    let baseline = CGPoint(x: x, y: y + ascent)
                    lines.append(TableLayout.Line(line: line, origin: baseline, width: width))
                    Self.collectRunDecorations(line, baseline: baseline, ascent: ascent, descent: descent,
                                               decorations: &decorations, attachments: &attachments, links: &links)
                    y += ascent + descent + Self.lineGap(for: (line, ascent, descent, width))
                }
                rowCells.append(TableLayout.Cell(row: row, column: column, lines: lines,
                                                 decorations: decorations, attachments: attachments))
            }
            cells.append(rowCells)
        }

        return TableLayout(
            columnOffsets: columnOffsets,
            rowOffsets: rowOffsets,
            cells: cells,
            links: links,
            plainRows: measured.map { $0.map(\.plain) },
            headerBackground: theme.tableHeaderBackground?.cgColor,
            stripeBackground: theme.tableStripe?.cgColor,
            borderColor: theme.tableBorder.cgColor,
            borderWidth: style.borderWidth,
            cornerRadius: theme.length(style.cornerRadius)
        )
    }

    private static func lineGap(for line: (CTLine, CGFloat, CGFloat, CGFloat)) -> CGFloat {
        ceil((line.1 + line.2) * 0.15)
    }

    private static func measure(_ string: NSAttributedString, plain: String) -> Measured {
        guard string.length > 0 else { return Measured(string: string, typesetter: nil, naturalWidth: 0, plain: plain) }
        let typesetter = CTTypesetterCreateWithAttributedString(string)
        // Natural width: widest hard line (cells rarely contain hard breaks).
        var width: CGFloat = 0
        var start = 0
        let length = string.length
        while start < length {
            let count = CTTypesetterSuggestLineBreak(typesetter, start, .greatestFiniteMagnitude)
            guard count > 0 else { break }
            let line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count))
            width = max(width, CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) - CGFloat(CTLineGetTrailingWhitespaceWidth(line)))
            start += count
        }
        return Measured(string: string, typesetter: typesetter, naturalWidth: ceil(width), plain: plain)
    }

    fileprivate static func breakLines(_ cell: Measured, width: CGFloat) -> [BrokenLine] {
        guard let typesetter = cell.typesetter else { return [] }
        var lines: [(CTLine, CGFloat, CGFloat, CGFloat)] = []
        var start = 0
        let length = cell.string.length
        while start < length {
            var count = CTTypesetterSuggestLineBreak(typesetter, start, Double(width) + 0.5)
            if count <= 0 { count = CTTypesetterSuggestClusterBreak(typesetter, start, Double(width) + 0.5) }
            if count <= 0 { count = length - start }
            let line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count))
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading)) - CGFloat(CTLineGetTrailingWhitespaceWidth(line))
            lines.append((line, ceil(ascent), ceil(descent), lineWidth))
            start += count
        }
        return lines
    }

    static func collectRunDecorations(_ line: CTLine, baseline: CGPoint, ascent: CGFloat, descent: CGFloat,
                                              decorations: inout [TableLayout.Decoration],
                                              attachments: inout [TableLayout.Attachment],
                                              links: inout [TableLayout.Link]) {
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]
        for run in runs {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let link = attributes[CoreTextKeys.link] as? URL
            let background = attributes[CoreTextKeys.background]
            let strike = attributes[CoreTextKeys.strikethrough] != nil
            let attachment = attributes[CoreTextKeys.attachment] as? CoreTextAttachment
            guard link != nil || background != nil || strike || attachment != nil else { continue }
            let range = CTRunGetStringRange(run)
            let startX = CTLineGetOffsetForStringIndex(line, range.location, nil)
            var runAscent: CGFloat = 0, runDescent: CGFloat = 0
            let width = CGFloat(CTRunGetTypographicBounds(run, CFRange(location: 0, length: 0), &runAscent, &runDescent, nil))
            let rect = CGRect(x: baseline.x + startX, y: baseline.y - runAscent, width: width, height: runAscent + runDescent)
            if let attachment {
                attachments.append(.init(attachment: attachment,
                                         rect: CGRect(x: rect.minX, y: baseline.y - attachment.ascent,
                                                      width: attachment.width, height: attachment.ascent + attachment.descent)))
            }
            if let background {
                decorations.append(.init(kind: .background, rect: rect.insetBy(dx: -2, dy: -1), color: background as! CGColor))
            }
            if strike, let color = attributes[CoreTextKeys.foreground] {
                let y = baseline.y - runAscent * 0.32
                decorations.append(.init(kind: .strikethrough, rect: CGRect(x: rect.minX, y: y, width: width, height: 1),
                                         color: color as! CGColor))
            }
            if let link { links.append(.init(rect: rect, url: link)) }
        }
    }

    /// Runs `work` over chunks of `0..<count` concurrently when the table is large enough to benefit.
    private static func parallel<T>(_ count: Int, cellCount: Int,
                                    work: (Range<Int>) -> [T], merge: ([T]) -> Void) {
        let workers = cellCount >= 256 ? min(Parallel.processorCount, max(1, count / 4)) : 1
        for result in Parallel.map(count, workers: workers, work) { merge(result) }
    }
}
