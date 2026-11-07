import SwiftUI
import CoreText

/// A fenced code block: header with language and copy button, highlighted code that scrolls
/// horizontally (or wraps, per style).
struct CodeBlockView: View {
    let code: PreparedCode
    let theme: ResolvedTheme

    var body: some View {
        let style = theme.theme.codeBlock
        let padding = theme.length(style.padding, fontScale: style.font.scale)
        let radius = theme.length(style.cornerRadius)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        VStack(alignment: .leading, spacing: 0) {
            if style.showsHeader {
                CodeHeader(code: code, theme: theme, padding: padding)
            }
            if code.usesCoreText {
                // Only pay for a scroll view when the code is wider than the container.
                ViewThatFits(in: .horizontal) {
                    CodeCanvas(code: code)
                        .padding(padding)
                    ScrollView(.horizontal) {
                        CodeCanvas(code: code)
                            .padding(padding)
                    }
                    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                }
            } else if style.wrapsLines {
                textLines.padding(padding)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal) {
                    textLines.padding(padding)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            }
        }
        .background(Color(theme.codeBackground), in: shape)
        .overlay {
            if let border = theme.codeBorder { shape.strokeBorder(Color(border), lineWidth: 1) }
        }
        .clipShape(shape)
        .accessibilityElement(children: .contain)
    }

    /// SwiftUI `Text` renderer.
    private var textLines: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(code.chunks) { chunk in
                Text(chunk.text ?? AttributedString())
                    .fixedSize(horizontal: !theme.theme.codeBlock.wrapsLines, vertical: true)
            }
        }
        .lineSpacing(code.fontSize * 0.25)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Code\(code.language.map { ", \($0)" } ?? "")")
        .accessibilityValue(code.code)
    }
}

/// Code lines typeset off the main thread, drawn in vertically tiled canvases.
private struct CodeCanvas: View {
    let code: PreparedCode

    static let tileLines = 60

    var body: some View {
        let lines = code.chunks.flatMap { $0.lines?.lines ?? [] }
        let tiles = stride(from: 0, to: max(lines.count, 1), by: Self.tileLines).map { $0..<min($0 + Self.tileLines, lines.count) }
        VStack(alignment: .leading, spacing: 0) {
            ForEach(tiles, id: \.lowerBound) { range in
                let tileLines = Array(lines[range])
                let height = CGFloat(range.count) * code.lineHeight
                let ascent = code.ascent
                let pitch = code.lineHeight
                Canvas(rendersAsynchronously: true) { context, _ in
                    context.withCGContext { cg in
                        cg.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
                        for (index, line) in tileLines.enumerated() {
                            cg.textPosition = CGPoint(x: 0, y: CGFloat(index) * pitch + ascent)
                            CTLineDraw(line, cg)
                        }
                    }
                }
                .frame(width: max(code.contentWidth, 1), height: max(height, 1))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Code\(code.language.map { ", \($0)" } ?? "")")
        .accessibilityValue(code.code)
    }
}

private struct CodeHeader: View {
    let code: PreparedCode
    let theme: ResolvedTheme
    let padding: CGFloat

    @State private var copied = false

    var body: some View {
        let font = Font.system(size: code.fontSize * 0.9, weight: .medium)
        let color = Color(theme.codeHeaderColor)
        HStack(spacing: 4) {
            Text(code.language?.lowercased() ?? "code")
            Spacer(minLength: 8)
            if !code.isClosed {
                ProgressView().controlSize(.mini)
            } else if theme.theme.codeBlock.showsCopyButton {
                Text("\(Image(systemName: copied ? "checkmark" : "doc.on.doc")) \(copied ? "Copied" : "Copy")")
                    .contentShape(Rectangle())
                    .onTapGesture { copy() }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(copied ? "Copied" : "Copy code")
                    .accessibilityAction { copy() }
            }
        }
        .font(font)
        .foregroundStyle(color)
        .padding(.horizontal, padding)
        .padding(.vertical, padding * 0.5)
        .background(Color(theme.codeHeaderBackground))
    }

    private func copy() {
        Pasteboard.copy(code.code)
        copied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}
