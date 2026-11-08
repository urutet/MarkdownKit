import SwiftUI
import MarkdownKit

/// Every supported construct on one page.
struct GalleryView: View {
    var body: some View {
        ScrollView {
            MarkdownView(SampleContent.gallery)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Gallery")
    }
}

struct SettingsView: View {
    @Environment(DemoSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Rendering") {
                // Selectable text always uses SwiftUI Text, so show that while it's on.
                Picker("Text renderer", selection: Binding(
                    get: { settings.selectableText ? .swiftUIText : settings.renderer },
                    set: { settings.renderer = $0 }
                )) {
                    Text("CoreText (fast)").tag(MarkdownTextRenderer.coreText)
                    Text("SwiftUI Text").tag(MarkdownTextRenderer.swiftUIText)
                }
                .disabled(settings.selectableText)
                Toggle("Selectable text (uses SwiftUI Text)", isOn: $settings.selectableText)
                Toggle("Chat: one lazy row per block", isOn: $settings.flattenBlocks)
                Toggle("Compact theme", isOn: $settings.compact)
            }
            Section("Code theme") {
                Picker("Theme", selection: $settings.codeTheme) {
                    ForEach(CodeTheme.allBuiltIn, id: \.name) { Text($0.name).tag($0) }
                }
            }
            Section("Dynamic Type") {
                Picker("Size", selection: $settings.dynamicTypeSize) {
                    ForEach(DynamicTypeSize.allCases, id: \.self) { Text(String(describing: $0)).tag($0) }
                }
            }
            Section("Cache") {
                Button("Clear Markdown caches") { MarkdownCache.shared.removeAll() }
            }
        }
        .navigationTitle("Settings")
    }
}
