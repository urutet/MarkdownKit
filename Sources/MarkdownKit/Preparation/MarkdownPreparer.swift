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
        guard cached else {
            return blocks.enumerated().map { index, block in
                let (content, spacing) = prepare(block, context: context)
                return PreparedBlock(id: index, key: Self.key(block, theme: theme, context: context),
                                     content: content, spacingBefore: spacing)
            }
        }
        // Top level: look up the block cache, then prepare the misses (in parallel when expensive).
        let keys = blocks.map { Self.key($0, theme: theme, context: context) }
        var entries: [PreparedBlockCache.Entry?] = keys.map { cache[$0] }
        let misses = entries.indices.filter { entries[$0] == nil }
        let totalCost = misses.reduce(0) { $0 + Self.cost(of: blocks[$1]) }
        let workers = misses.count > 1 && totalCost > 200_000 ? Parallel.processorCount : 1
        let prepared = Parallel.map(misses.count, workers: workers) { range in
            range.map { i -> PreparedBlockCache.Entry in
                let block = blocks[misses[i]]
                let (content, spacing) = prepare(block, context: context)
                return .init(content: content, spacingBefore: spacing, cost: Self.cost(of: block))
            }
        }.flatMap { $0 }
        for (i, entry) in zip(misses, prepared) {
            entries[i] = entry
            cache[keys[i]] = entry
        }
        return entries.enumerated().map { index, entry in
            PreparedBlock(id: index, key: keys[index], content: entry!.content, spacingBefore: entry!.spacingBefore)
        }
    }

    static func key(_ block: MarkdownBlock, theme: ResolvedTheme, context: Context) -> Int {
        var hasher = Hasher()
        hasher.combine(block)
        hasher.combine(theme.fingerprint)
        hasher.combine(context)
        return hasher.finalize()
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
        .code(CodeHighlighting(theme: theme).prepare(code))
    }

    private func prepareTable(_ table: MarkdownTable, context: Context) -> PreparedContent {
        .table(TableLayoutEngine(theme: theme, math: math, textColor: textColor(context)).layout(table))
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
