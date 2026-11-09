import SwiftUI

/// A monospaced text editor for Markdown source: no smart dashes, smart quotes, autocorrection or
/// autocapitalization. (SwiftUI's `TextEditor` can't turn off smart punctuation, which turns a table's
/// `---` into an em dash and breaks quotes in code.)
struct PlainTextEditor {
    @Binding var text: String
    /// Shows the keyboard when the editor appears.
    var startsFocused = false

    final class Coordinator: NSObject {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }
}

#if canImport(UIKit)
import UIKit

extension PlainTextEditor: UIViewRepresentable {
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.text = text
        view.font = UIFontMetrics(forTextStyle: .callout)
            .scaledFont(for: .monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .callout).pointSize, weight: .regular))
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        view.smartDashesType = .no
        view.smartQuotesType = .no
        view.smartInsertDeleteType = .no
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.spellCheckingType = .no
        view.keyboardDismissMode = .interactive
        if startsFocused {
            DispatchQueue.main.async { view.becomeFirstResponder() }
        }
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.text = $text
        if view.text != text { view.text = text }
    }
}

extension PlainTextEditor.Coordinator: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        text.wrappedValue = textView.text
    }
}
#else
import AppKit

extension PlainTextEditor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let view = scrollView.documentView as! NSTextView
        view.delegate = context.coordinator
        view.string = text
        view.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        view.isRichText = false
        view.allowsUndo = true
        view.textContainerInset = NSSize(width: 8, height: 8)
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.drawsBackground = false
        scrollView.drawsBackground = false
        if startsFocused {
            DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let view = scrollView.documentView as? NSTextView, view.string != text else { return }
        view.string = text
    }
}

extension PlainTextEditor.Coordinator: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard let view = notification.object as? NSTextView else { return }
        text.wrappedValue = view.string
    }
}
#endif
