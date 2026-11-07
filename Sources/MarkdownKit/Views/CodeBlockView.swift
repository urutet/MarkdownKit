import SwiftUI

/// A fenced code block: header with language and copy button, highlighted code that scrolls
/// horizontally (or wraps, per style).
struct CodeBlockView: View {
    let code: PreparedCode
    let theme: ResolvedTheme

    @State private var copied = false

    var body: some View {
        let style = theme.theme.codeBlock
        let padding = theme.length(style.padding, fontScale: style.font.scale)
        let radius = theme.length(style.cornerRadius)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        VStack(alignment: .leading, spacing: 0) {
            if style.showsHeader {
                header(padding: padding)
            }
            if style.wrapsLines {
                lines.padding(padding)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal) {
                    lines.padding(padding)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            }
        }
        .background(Color(theme.codeBackground), in: shape)
        .overlay {
            if let border = theme.codeBorder { shape.strokeBorder(Color(border), lineWidth: 1) }
        }
        .clipShape(shape)
    }

    private var lines: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(code.chunks) { chunk in
                Text(chunk.text)
                    .fixedSize(horizontal: !theme.theme.codeBlock.wrapsLines, vertical: true)
            }
        }
        .lineSpacing(code.fontSize * 0.25)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Code\(code.language.map { ", \($0)" } ?? "")")
        .accessibilityValue(code.code)
    }

    private func header(padding: CGFloat) -> some View {
        HStack {
            Text(code.language?.lowercased() ?? "code")
                .font(.system(size: code.fontSize * 0.9, weight: .medium))
                .foregroundStyle(Color(theme.codeHeaderColor))
            Spacer(minLength: 8)
            if !code.isClosed {
                ProgressView().controlSize(.mini)
            } else if theme.theme.codeBlock.showsCopyButton {
                Button {
                    Pasteboard.copy(code.code)
                    copied = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: code.fontSize * 0.9, weight: .medium))
                        .foregroundStyle(Color(theme.codeHeaderColor))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(copied ? "Copied" : "Copy code")
            }
        }
        .padding(.horizontal, padding)
        .padding(.vertical, padding * 0.5)
        .background(Color(theme.codeHeaderBackground))
    }
}
