import SwiftUI

/// Lays out prepared blocks vertically.
struct MarkdownDocumentView: View {
    let document: PreparedDocument
    let theme: ResolvedTheme

    var body: some View {
        BlockStack(blocks: document.blocks, theme: theme, spacing: theme.length(theme.theme.blockSpacing))
    }
}

struct BlockStack: View {
    let blocks: [PreparedBlock]
    let theme: ResolvedTheme
    let spacing: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(blocks) { block in
                BlockView(block: block, theme: theme, isFirst: block.id == 0)
                    .equatable()
            }
        }
    }
}

/// Renders one block. `Equatable` on the block's content key so unchanged blocks are skipped while
/// streaming.
struct BlockView: View, Equatable {
    let block: PreparedBlock
    let theme: ResolvedTheme
    let isFirst: Bool

    nonisolated static func == (lhs: BlockView, rhs: BlockView) -> Bool {
        lhs.block == rhs.block && lhs.isFirst == rhs.isFirst
    }

    var body: some View {
        content
            .padding(.top, isFirst ? 0 : block.spacingBefore)
    }

    @ViewBuilder private var content: some View {
        switch block.content {
        case .text(let text, let role):
            TextBlockView(text: text, role: role, theme: theme)
        case .blockquote(let blocks):
            BlockquoteView(blocks: blocks, theme: theme)
        case .list(let list):
            ListBlockView(list: list, theme: theme)
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
        VStack(alignment: .leading, spacing: list.itemSpacing) {
            ForEach(list.items) { item in
                HStack(alignment: .firstTextBaseline, spacing: list.markerSpacing) {
                    marker(item.marker)
                        .frame(width: list.markerWidth, alignment: .trailing)
                    BlockStack(blocks: item.blocks, theme: theme, spacing: list.itemSpacing)
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
