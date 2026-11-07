import SwiftUI
import os

/// Turns parsed blocks into render-ready ``PreparedBlock``s. Thread-safe; meant to run off the main actor.
struct MarkdownPreparer: Sendable {
    let theme: ResolvedTheme
    let math: (any MathRendering)?
    let cache: PreparedBlockCache

    init(theme: ResolvedTheme, math: (any MathRendering)? = nil, cache: PreparedBlockCache = .shared) {
        self.theme = theme
        self.math = math
        self.cache = cache
    }

    struct Context: Hashable {
        var listDepth = 0
        var inQuote = false
    }

    func prepare(_ blocks: [MarkdownBlock], key: Int) -> PreparedDocument {
        let state = Signposts.prepare.beginInterval("prepare")
        defer { Signposts.prepare.endInterval("prepare", state) }
        return PreparedDocument(blocks: prepareBlocks(blocks, context: Context(), cached: true), key: key)
    }

    func prepareBlocks(_ blocks: [MarkdownBlock], context: Context, cached: Bool = false) -> [PreparedBlock] {
        var result: [PreparedBlock] = []
        result.reserveCapacity(blocks.count)
        for (index, block) in blocks.enumerated() {
            var hasher = Hasher()
            hasher.combine(block)
            hasher.combine(theme.fingerprint)
            hasher.combine(context)
            let key = hasher.finalize()
            if cached, let hit = cache[key] {
                result.append(PreparedBlock(id: index, key: key, content: hit.content, spacingBefore: hit.spacingBefore))
                continue
            }
            let (content, spacing) = prepare(block, context: context)
            if cached { cache[key] = .init(content: content, spacingBefore: spacing, cost: Self.cost(of: block)) }
            result.append(PreparedBlock(id: index, key: key, content: content, spacingBefore: spacing))
        }
        return result
    }

    private func textColor(_ context: Context) -> Color.Resolved {
        context.inQuote ? (theme.quoteTextColor ?? theme.textColor) : theme.textColor
    }

    private func prepare(_ block: MarkdownBlock, context: Context) -> (PreparedContent, CGFloat) {
        let t = theme.theme
        switch block {
        case .paragraph(let inlines):
            if inlines.count == 1, case .image(let source, let alt, let title) = inlines[0] {
                return (.image(PreparedImage(url: source.flatMap(InlineBuilder.url(from:)), alt: alt, title: title)), 0)
            }
            let style = InlineBuilder.Style(font: t.text.font, color: textColor(context))
            let text = InlineBuilder.build(inlines, style: style, theme: theme, math: math,
                                           lineSpacing: theme.length(t.text.lineSpacing))
            return (.text(text, .paragraph), 0)

        case .heading(let level, let inlines):
            let heading = t.heading(level)
            let color = theme.headingColors[min(max(level, 1), theme.headingColors.count) - 1] ?? textColor(context)
            let style = InlineBuilder.Style(font: heading.font, color: color)
            let text = InlineBuilder.build(inlines, style: style, theme: theme, math: math,
                                           lineSpacing: theme.length(t.text.lineSpacing, fontScale: heading.font.scale) * 0.5)
            return (.text(text, .heading(level)), theme.length(heading.spacingBefore, fontScale: heading.font.scale))

        case .blockquote(let children):
            var inner = context
            inner.inQuote = true
            return (.blockquote(prepareBlocks(children, context: inner)), 0)

        case .list(let list):
            return (.list(prepareList(list, context: context)), 0)

        case .codeBlock(let code):
            return (prepareCode(code), 0)

        case .table(let table):
            return (prepareTable(table, context: context), 0)

        case .thematicBreak:
            return (.thematicBreak, 0)

        case .mathBlock(let latex):
            let fontSize = theme.size(t.text.font) * t.math.scale
            let rendered = math?.render(latex: latex, display: true, fontSize: fontSize, color: theme.mathColor, font: t.math.font)
            var fallback = AttributedString(latex)
            fallback.font = theme.font(.monospaced)
            fallback.foregroundColor = Color(theme.secondaryColor)
            return (.math(PreparedMath(latex: latex, isDisplay: true, image: rendered?.image,
                                       descent: rendered?.descent ?? 0, fallback: fallback)), 0)

        case .htmlBlock(let html):
            let style = InlineBuilder.Style(font: .monospaced, color: theme.secondaryColor)
            let text = InlineBuilder.build([.text(html)], style: style, theme: theme, math: nil, lineSpacing: 0)
            return (.text(text, .html), 0)
        }
    }

    private func prepareList(_ list: MarkdownList, context: Context) -> PreparedList {
        let t = theme.theme
        var inner = context
        inner.listDepth += 1
        let bullets = t.list.bullets.isEmpty ? ["•"] : t.list.bullets
        let bullet = bullets[context.listDepth % bullets.count]
        let markerColor = theme.listMarkerColor ?? textColor(context)
        let maxNumber = list.startIndex + list.items.count - 1
        let digits = String(maxNumber).count
        let fontSize = theme.size(t.text.font)

        var items: [PreparedListItem] = []
        items.reserveCapacity(list.items.count)
        for (index, item) in list.items.enumerated() {
            let marker: ListMarker
            if let checked = item.checkbox {
                let color = checked ? theme.checkedColor : theme.uncheckedColor
                marker = .checkbox(checked, size: fontSize, color: color)
            } else {
                var text = AttributedString(list.isOrdered ? "\(list.startIndex + index)." : bullet)
                text.font = theme.font(t.text.font).monospacedDigit()
                text.foregroundColor = Color(markerColor)
                marker = .text(text)
            }
            items.append(PreparedListItem(id: index, marker: marker, blocks: prepareBlocks(item.blocks, context: inner)))
        }
        let markerWidth = list.isOrdered
            ? max(theme.length(t.list.markerWidth), fontSize * (0.62 * CGFloat(digits) + 0.4))
            : theme.length(t.list.markerWidth)
        return PreparedList(items: items, markerWidth: markerWidth,
                            markerSpacing: theme.length(t.list.markerSpacing),
                            itemSpacing: list.isTight ? theme.length(t.list.itemSpacing) : theme.length(t.blockSpacing))
    }

    private func prepareCode(_ code: MarkdownCodeBlock) -> PreparedContent {
        let style = InlineBuilder.Style(font: theme.theme.codeBlock.font, color: theme.textColor)
        let text = InlineBuilder.build([.text(code.code)], style: style, theme: theme, math: nil, lineSpacing: 0)
        return .text(text, .html)
    }

    private func prepareTable(_ table: MarkdownTable, context: Context) -> PreparedContent {
        var lines: [MarkdownInline] = []
        for row in [table.header] + table.rows {
            lines.append(.text(row.map(\.plainText).joined(separator: " | ")))
            lines.append(.lineBreak)
        }
        let style = InlineBuilder.Style(font: theme.theme.table.font, color: textColor(context))
        return .text(InlineBuilder.build(lines, style: style, theme: theme, math: math, lineSpacing: 0), .paragraph)
    }

    static func cost(of block: MarkdownBlock) -> Int {
        switch block {
        case .table(let table): 64 * table.columnCount * (table.rows.count + 1)
        case .codeBlock(let code): code.code.utf8.count * 2
        default: 256
        }
    }
}

enum Signposts {
    static let parse = OSSignposter(subsystem: "MarkdownKit", category: "Parse")
    static let prepare = OSSignposter(subsystem: "MarkdownKit", category: "Prepare")
}
