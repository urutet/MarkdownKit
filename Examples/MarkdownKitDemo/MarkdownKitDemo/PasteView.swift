import SwiftUI
import MarkdownKit

/// Paste or type your own Markdown and see it rendered. The text is kept between launches.
struct PasteView: View {
    enum Mode: String, CaseIterable {
        case edit = "Edit"
        case preview = "Preview"
    }

    @AppStorage("pastedMarkdown") private var text = PasteView.placeholder
    @State private var mode: Mode = .preview

    var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            switch mode {
            case .edit:
                editor
            case .preview:
                preview
            }
        }
        .navigationTitle("Paste")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var editor: some View {
        // The tab opens in Preview, so the editor only appears when the user taps Edit: show the keyboard.
        PlainTextEditor(text: $text, startsFocused: true)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Type or paste Markdown here")
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 17)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
    }

    @ViewBuilder private var preview: some View {
        if text.isEmpty {
            ContentUnavailableView("Nothing to preview", systemImage: "doc.on.clipboard",
                                   description: Text("Paste or type Markdown under Edit."))
        } else {
            ScrollView {
                // MarkdownBlocks keeps long pasted documents lazy: only visible blocks are built.
                LazyVStack(alignment: .leading, spacing: 0) {
                    MarkdownBlocks(text)
                }
                .padding()
            }
        }
    }

    static let placeholder = """
    # Your Markdown

    Copy Markdown from anywhere (a chat reply, a README…), switch to **Edit** and paste it over this \
    text, or type your own. Then switch back to **Preview**.

    - Tables, code, math ($e^{i\\pi} + 1 = 0$) and images all work
    - The text is kept between launches
    """
}
