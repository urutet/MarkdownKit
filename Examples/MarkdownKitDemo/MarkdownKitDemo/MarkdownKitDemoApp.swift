import SwiftUI
import MarkdownKit

@main
struct MarkdownKitDemoApp: App {
    @State private var settings = DemoSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .markdownTheme(settings.theme)
                .markdownTextRenderer(settings.renderer)
                .dynamicTypeSize(settings.dynamicTypeSize)
                .markdownEmojiProvider(SampleContent.emojiProvider)
                .markdownAnimatesImages(!UserDefaults.standard.bool(forKey: "noanim"))
        }
    }
}

struct RootView: View {
    /// `-tab gallery` (etc.) selects the initial tab, handy for automation.
    @State private var selection = UserDefaults.standard.string(forKey: "tab") ?? "chat"

    var body: some View {
        TabView(selection: $selection) {
            Tab("Chat", systemImage: "bubble.left.and.bubble.right", value: "chat") { NavigationStack { ChatView() } }
            Tab("Streaming", systemImage: "text.cursor", value: "streaming") { NavigationStack { StreamingView() } }
            Tab("Gallery", systemImage: "square.grid.2x2", value: "gallery") { NavigationStack { GalleryView() } }
            Tab("Benchmark", systemImage: "speedometer", value: "benchmark") { NavigationStack { BenchmarkView() } }
            Tab("Settings", systemImage: "gearshape", value: "settings") { NavigationStack { SettingsView() } }
        }
    }
}

/// App-wide demo settings.
@Observable
final class DemoSettings {
    var codeTheme: CodeTheme = .xcode
    var compact = false
    var dynamicTypeSize: DynamicTypeSize = .large
    var renderer: MarkdownTextRenderer = UserDefaults.standard.string(forKey: "renderer") == "text" ? .swiftUIText : .coreText
    /// Chat uses MarkdownBlocks (one lazy row per block) instead of one MarkdownView per message.
    var flattenBlocks = UserDefaults.standard.object(forKey: "flatten") == nil || UserDefaults.standard.bool(forKey: "flatten")

    var theme: MarkdownTheme {
        var theme = compact ? MarkdownTheme.compact : .default
        theme.codeBlock.theme = codeTheme
        return theme
    }
}
