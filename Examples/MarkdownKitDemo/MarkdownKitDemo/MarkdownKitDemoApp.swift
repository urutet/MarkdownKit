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
    /// `-tab gallery` (etc.) selects the initial tab, handy for automation. `-tab benchmark` opens the
    /// scroll benchmark, which lives in Settings (five tabs fit an iPhone tab bar without "More").
    @State private var selection: String
    @State private var settingsPath: [SettingsDestination]

    init() {
        let tab = UserDefaults.standard.string(forKey: "tab") ?? "chat"
        _selection = State(initialValue: tab == "benchmark" ? "settings" : tab)
        _settingsPath = State(initialValue: tab == "benchmark" ? [.benchmark] : [])
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Chat", systemImage: "bubble.left.and.bubble.right", value: "chat") { NavigationStack { ChatView() } }
            Tab("Streaming", systemImage: "text.cursor", value: "streaming") { NavigationStack { StreamingView() } }
            Tab("Gallery", systemImage: "square.grid.2x2", value: "gallery") { NavigationStack { GalleryView() } }
            Tab("Paste", systemImage: "doc.on.clipboard", value: "paste") { NavigationStack { PasteView() } }
            Tab("Settings", systemImage: "gearshape", value: "settings") {
                NavigationStack(path: $settingsPath) {
                    SettingsView()
                        .navigationDestination(for: SettingsDestination.self) { destination in
                            switch destination {
                            case .benchmark: BenchmarkView()
                            }
                        }
                }
            }
        }
    }
}

enum SettingsDestination: Hashable {
    case benchmark
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
