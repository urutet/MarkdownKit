import SwiftUI

/// Lays out prepared blocks vertically.
struct MarkdownDocumentView: View {
    let document: PreparedDocument
    let theme: ResolvedTheme
    var showsCursor = false

    var body: some View {
        BlockStack(blocks: document.blocks, theme: theme, spacing: theme.length(theme.theme.blockSpacing),
                   cursorOnLast: showsCursor)
    }
}

struct BlockStack: View {
    let blocks: [PreparedBlock]
    let theme: ResolvedTheme
    let spacing: CGFloat
    var cursorOnLast = false

    var body: some View {
        let lastID = blocks.last?.id
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(blocks) { block in
                BlockView(block: block, theme: theme, isFirst: block.id == 0,
                          showsCursor: cursorOnLast && block.id == lastID)
                    .equatable()
            }
            if cursorOnLast && blocks.isEmpty {
                StreamingCursor(theme: theme)
            }
        }
    }
}

/// Pulsing dot shown after streaming content that doesn't end in text.
struct StreamingCursor: View {
    let theme: ResolvedTheme

    var body: some View {
        Circle()
            .fill(Color(theme.textColor))
            .frame(width: theme.baseSize * 0.55, height: theme.baseSize * 0.55)
            .phaseAnimator([0.35, 1.0]) { view, opacity in
                view.opacity(opacity)
            } animation: { _ in .easeInOut(duration: 0.6) }
            .padding(.vertical, theme.baseSize * 0.2)
            .accessibilityHidden(true)
    }
}

/// Renders one block. `Equatable` on the block's content key so unchanged blocks are skipped while
/// streaming.
struct BlockView: View, Equatable {
    let block: PreparedBlock
    let theme: ResolvedTheme
    let isFirst: Bool
    var showsCursor = false

    nonisolated static func == (lhs: BlockView, rhs: BlockView) -> Bool {
        lhs.block == rhs.block && lhs.isFirst == rhs.isFirst && lhs.showsCursor == rhs.showsCursor
    }

    var body: some View {
        let spacing = isFirst ? 0 : block.spacingBefore
        // Keep the view tree minimal: wrappers only when needed.
        if showsCursor, !block.content.isText {
            VStack(alignment: .leading, spacing: theme.length(theme.theme.blockSpacing) * 0.5) {
                content
                StreamingCursor(theme: theme)
            }
            .padding(.top, spacing)
        } else if spacing > 0 {
            content.padding(.top, spacing)
        } else {
            content
        }
    }

    @ViewBuilder private var content: some View {
        switch block.content {
        case .text(let text, let role):
            TextBlockView(text: text, role: role, theme: theme, showsCursor: showsCursor)
        case .blockquote(let blocks, let stack):
            if let stack {
                RichTextView(stack: stack, theme: theme)
            } else {
                BlockquoteView(blocks: blocks, theme: theme)
            }
        case .list(let list):
            if let stack = list.stack {
                // The whole list in one canvas.
                RichTextView(stack: stack, theme: theme)
            } else {
                ListBlockView(list: list, theme: theme)
            }
        case .table(let layout):
            TableBlockView(layout: layout)
        case .code(let code):
            CodeBlockView(code: code, theme: theme)
        case .math(let math):
            MathBlockView(math: math)
        case .image(let image):
            BlockImageView(image: image, theme: theme)
        case .thematicBreak:
            Rectangle()
                .fill(Color(theme.ruleColor))
                .frame(height: theme.theme.thematicBreak.thickness)
                .padding(.vertical, theme.length(theme.theme.thematicBreak.spacing))
                .accessibilityHidden(true)
        }
    }
}

struct BlockquoteView: View {
    let blocks: [PreparedBlock]
    let theme: ResolvedTheme

    var body: some View {
        let style = theme.theme.blockquote
        let barWidth = theme.length(style.barWidth)
        BlockStack(blocks: blocks, theme: theme, spacing: theme.length(theme.theme.blockSpacing))
            .padding(.leading, barWidth + theme.length(style.indent))
            .padding(.vertical, theme.quoteBackground == nil ? 0 : theme.length(.em(0.4)))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .leading) {
                ZStack(alignment: .leading) {
                    if let background = theme.quoteBackground { Color(background) }
                    Rectangle().fill(Color(theme.quoteBarColor)).frame(width: barWidth)
                }
            }
    }
}

struct ListBlockView: View {
    let list: PreparedList
    let theme: ResolvedTheme

    var body: some View {
        let indent = list.markerWidth + list.markerSpacing
        VStack(alignment: .leading, spacing: list.itemSpacing) {
            ForEach(list.items) { item in
                if let first = item.blocks.first, case .text(let text, .paragraph) = first.content, let rich = text.rich {
                    // Fast path: the marker is drawn inside the item's text view (hanging indent).
                    let rest = Array(item.blocks.dropFirst())
                    if rest.isEmpty {
                        RichTextView(text: rich, theme: theme, marker: item.marker, markerLine: item.markerLine, indent: indent,
                                     markerWidth: list.markerWidth)
                    } else {
                        VStack(alignment: .leading, spacing: list.itemSpacing) {
                            RichTextView(text: rich, theme: theme, marker: item.marker, markerLine: item.markerLine, indent: indent,
                                     markerWidth: list.markerWidth)
                            BlockStack(blocks: rest, theme: theme, spacing: list.itemSpacing)
                                .padding(.leading, indent)
                        }
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: list.markerSpacing) {
                        marker(item.marker)
                            .frame(width: list.markerWidth, alignment: .trailing)
                        BlockStack(blocks: item.blocks, theme: theme, spacing: list.itemSpacing)
                    }
                }
            }
        }
    }

    @ViewBuilder private func marker(_ marker: ListMarker) -> some View {
        switch marker {
        case .text(let text):
            Text(text).accessibilityHidden(true)
        case .checkbox(let checked, let size, let color):
            Text(Image(systemName: checked ? "checkmark.square.fill" : "square"))
                .font(.system(size: size * 0.95))
                .foregroundStyle(Color(color))
                .accessibilityLabel(checked ? "Completed" : "Not completed")
        }
    }
}

struct MathBlockView: View {
    let math: PreparedMath

    var body: some View {
        if let image = math.image {
            let view = Image(decorative: image.cgImage, scale: image.scale)
                .accessibilityLabel(math.latex)
            ViewThatFits(in: .horizontal) {
                view.frame(maxWidth: .infinity)
                ScrollView(.horizontal, showsIndicators: false) { view }
            }
        } else {
            Text(math.fallback)
                .frame(maxWidth: .infinity)
        }
    }
}

extension PreparedContent {
    var isText: Bool {
        if case .text = self { return true }
        return false
    }
}
