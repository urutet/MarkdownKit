import SwiftUI
import QuartzCore
import MarkdownKit

/// 200 messages with prose, code, math, animated images and 30×30 tables in a lazy list.
struct ChatView: View {
    @Environment(DemoSettings.self) private var settings
    @State private var width: CGFloat?

    var body: some View {
        ScrollView {
            ChatTranscript(flatten: settings.flattenBlocks)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
        // Warm the cache (parse, prepare and typeset at the display width) before cells appear.
        .markdownPrefetch(SampleContent.conversation.filter { !$0.isUser }.map(\.text),
                          width: width.map { $0 - 2 * ChatTranscript.padding })
        .navigationTitle("Chat")
    }
}

struct ChatTranscript: View {
    let flatten: Bool
    static let padding: CGFloat = 16

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(SampleContent.conversation) { message in
                Color.clear.frame(height: 20)
                    .onAppear {
                        if UserDefaults.standard.bool(forKey: "log") {
                            print(String(format: "APPEAR %.3f message %d", CACurrentMediaTime(), message.id))
                        }
                    }
                if message.isUser {
                    UserBubble(text: message.text)
                } else if flatten {
                    // One lazy row per block: long answers only create what's on screen.
                    MarkdownBlocks(message.text)
                        .padding(.horizontal, Self.padding)
                } else {
                    MarkdownView(message.text)
                        .padding(.horizontal, Self.padding)
                }
            }
        }
        .padding(.bottom, 40)
    }
}

struct UserBubble: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 60)
            MarkdownView(text)
                .markdownTheme { $0.text.color = .white; $0.link.color = .white }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(.horizontal, ChatTranscript.padding)
    }
}
