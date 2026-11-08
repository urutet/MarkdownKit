import SwiftUI
import CoreText

/// Renders a table from its precomputed ``TableLayout``.
///
/// The table scrolls horizontally when wider than the container. It is drawn by a few `Canvas` tiles
/// (lazily created as they scroll into view, rendered asynchronously off the main thread) instead of
/// one `Text` per cell, so a 30×30 table costs a handful of views instead of 900.
struct TableBlockView: View {
    let layout: TableLayout

    @Environment(\.openURL) private var openURL

    /// Each tile is its own layer with a fixed rendering cost, so fewer, larger tiles scroll in more
    /// cheaply (measured: 512×768 → 1024×1024 cut table scroll hitches by about a third).
    static let tileWidth: CGFloat = 1024
    static let tileHeight: CGFloat = 1024

    var body: some View {
        let size = layout.size
        let columnTiles = layout.columnTiles(maxWidth: Self.tileWidth)
        let rowTiles = layout.rowTiles(maxHeight: Self.tileHeight)
        let shape = RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)

        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 0) {
                ForEach(columnTiles, id: \.lowerBound) { columns in
                    VStack(spacing: 0) {
                        ForEach(rowTiles, id: \.lowerBound) { rows in
                            TableTile(layout: layout, columns: columns, rows: rows)
                        }
                    }
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipShape(shape)
            .overlay { shape.strokeBorder(Color(cgColor: layout.borderColor), lineWidth: layout.borderWidth) }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                if let url = layout.link(at: location) { openURL(url) }
            }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .frame(height: size.height)
        .contextMenu {
            Button("Copy Table", systemImage: "doc.on.doc") { Pasteboard.copy(layout.markdown) }
            Button("Copy as TSV", systemImage: "tablecells") { Pasteboard.copy(layout.tsv) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Table, \(layout.columnCount) columns, \(max(layout.rowCount - 1, 0)) rows")
        .accessibilityValue(layout.plainRows.first?.joined(separator: ", ") ?? "")
    }
}

/// One rectangular tile of a table, drawn with CoreText inside an asynchronously rendered `Canvas`.
private struct TableTile: View, Equatable {
    let layout: TableLayout
    let columns: Range<Int>
    let rows: Range<Int>

    nonisolated static func == (lhs: TableTile, rhs: TableTile) -> Bool {
        lhs.columns == rhs.columns && lhs.rows == rhs.rows
            && lhs.layout.columnOffsets == rhs.layout.columnOffsets && lhs.layout.rowOffsets == rhs.layout.rowOffsets
            && lhs.layout.cells.count == rhs.layout.cells.count
    }

    var body: some View {
        let origin = CGPoint(x: layout.columnOffsets[columns.lowerBound], y: layout.rowOffsets[rows.lowerBound])
        let size = CGSize(width: layout.columnOffsets[columns.upperBound] - origin.x,
                          height: layout.rowOffsets[rows.upperBound] - origin.y)
        Canvas(rendersAsynchronously: true) { context, _ in
            context.withCGContext { cg in
                TableRenderer.draw(layout, columns: columns, rows: rows, origin: origin, drawsImages: false, in: cg)
            }
            // Math images are drawn natively by SwiftUI rather than through Core Graphics.
            for row in rows {
                for column in columns {
                    for attachment in layout.cells[row][column].attachments {
                        guard case .image(let image, _) = attachment.attachment.content else { continue }
                        context.draw(Image(decorative: image.cgImage, scale: image.scale),
                                     in: attachment.rect.offsetBy(dx: -origin.x, dy: -origin.y))
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

enum TableRenderer {
    /// Draws the cells in `columns`×`rows` into a top-left-origin context translated by `-origin`.
    static func draw(_ layout: TableLayout, columns: Range<Int>, rows: Range<Int>, origin: CGPoint, drawsImages: Bool = true,
                     in cg: CGContext) {
        cg.translateBy(x: -origin.x, y: -origin.y)
        let minX = layout.columnOffsets[columns.lowerBound]
        let maxX = layout.columnOffsets[columns.upperBound]

        // Backgrounds.
        for row in rows {
            let color: CGColor? = row == 0 ? layout.headerBackground : (row % 2 == 0 ? layout.stripeBackground : nil)
            guard let color else { continue }
            cg.setFillColor(color)
            cg.fill(CGRect(x: minX, y: layout.rowOffsets[row], width: maxX - minX,
                           height: layout.rowOffsets[row + 1] - layout.rowOffsets[row]))
        }

        // Grid lines (outer border is drawn by the view's rounded overlay).
        let lineWidth = layout.borderWidth
        cg.setFillColor(layout.borderColor)
        for row in rows where row > 0 {
            cg.fill(CGRect(x: minX, y: layout.rowOffsets[row] - lineWidth / 2, width: maxX - minX, height: lineWidth))
        }
        let minY = layout.rowOffsets[rows.lowerBound]
        let maxY = layout.rowOffsets[rows.upperBound]
        for column in columns where column > 0 {
            cg.fill(CGRect(x: layout.columnOffsets[column] - lineWidth / 2, y: minY, width: lineWidth, height: maxY - minY))
        }

        // Text.
        cg.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        for row in rows {
            let cells = layout.cells[row]
            for column in columns {
                let cell = cells[column]
                for decoration in cell.decorations where decoration.kind == .background {
                    cg.setFillColor(decoration.color)
                    cg.addPath(CGPath(roundedRect: decoration.rect, cornerWidth: 3, cornerHeight: 3, transform: nil))
                    cg.fillPath()
                }
                for line in cell.lines {
                    cg.textPosition = line.origin
                    CTLineDraw(line.line, cg)
                }
                for decoration in cell.decorations where decoration.kind == .strikethrough {
                    cg.setFillColor(decoration.color)
                    cg.fill(decoration.rect)
                }
                for attachment in cell.attachments where drawsImages {
                    guard case .image(let image, _) = attachment.attachment.content else { continue }
                    CoreTextDrawing.drawImage(image.cgImage, in: attachment.rect, context: cg)
                }
            }
        }
    }
}

enum Pasteboard {
    @MainActor static func copy(_ string: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = string
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}
