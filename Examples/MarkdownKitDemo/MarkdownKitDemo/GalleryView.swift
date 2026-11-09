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
                Picker("Text renderer", selection: $settings.renderer) {
                    Text("SwiftUI Text (selectable)").tag(MarkdownTextRenderer.swiftUIText)
                    Text("CoreText (fastest)").tag(MarkdownTextRenderer.coreText)
                }
                // CoreText text can't be selected.
                Toggle("Selectable text", isOn: $settings.selectableText)
                    .disabled(settings.renderer == .coreText)
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
                    Text("System").tag(DynamicTypeSize?.none)
                    ForEach(DynamicTypeSize.allCases, id: \.self) { Text(String(describing: $0)).tag(Optional($0)) }
                }
            }
            Section("Cache") {
                Button("Clear Markdown caches") { MarkdownCache.shared.removeAll() }
            }
            Section("Performance") {
                NavigationLink("Scroll benchmark", value: SettingsDestination.benchmark)
            }
        }
        .navigationTitle("Settings")
    }
}
