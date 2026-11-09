import SwiftUI
import MarkdownKit

@main
struct MarkdownKitDemoApp: App {
    @State private var settings = DemoSettings()

    var body: some Scene {
        WindowGroup {
            DemoRoot(settings: settings)
        }
    }
}

/// Applies the demo settings. Dynamic Type follows the system unless a size is picked in Settings.
struct DemoRoot: View {
    let settings: DemoSettings
    @Environment(\.dynamicTypeSize) private var systemDynamicTypeSize

    var body: some View {
        RootView()
            .markdownTextRenderer(settings.renderer)
            .markdownTextSelection(settings.selectableText)
            .environment(settings)
            .markdownTheme(settings.theme)
            .dynamicTypeSize(settings.dynamicTypeSize ?? systemDynamicTypeSize)
            .markdownEmojiProvider(SampleContent.emojiProvider)
            .markdownAnimatesImages(!UserDefaults.standard.bool(forKey: "noanim"))
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
    /// Selectable text (on by default; only the SwiftUI Text renderer supports it). `-selectable NO` turns it off.
    var selectableText = UserDefaults.standard.object(forKey: "selectable") == nil || UserDefaults.standard.bool(forKey: "selectable")
    /// `nil` follows the system text size setting.
    var dynamicTypeSize: DynamicTypeSize?
    /// `-renderer coretext` selects the CoreText renderer at launch (SwiftUI Text is the default).
    var renderer: MarkdownTextRenderer = UserDefaults.standard.string(forKey: "renderer") == "coretext" ? .coreText : .default
    /// Chat uses MarkdownBlocks (one lazy row per block) instead of one MarkdownView per message.
    var flattenBlocks = UserDefaults.standard.object(forKey: "flatten") == nil || UserDefaults.standard.bool(forKey: "flatten")

    var theme: MarkdownTheme {
        var theme = compact ? MarkdownTheme.compact : .default
        theme.codeBlock.theme = codeTheme
        return theme
    }
}
