import SwiftUI
import AppKit

/// NSTextView をラップした入力欄。text を双方向同期し、選択（未選択ならカーソル直前の
/// 1書記素）を onSelectionChange で報告する。macOS 14 の TextEditor が選択 API を
/// 持たないための AppKit ラップ。
struct CodePointTextView: NSViewRepresentable {
    @Binding var text: String
    var onSelectionChange: (String) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.allowsUndo = true
        textView.string = text

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // 最新のクロージャ/バインディングを Coordinator に反映する。
        context.coordinator.parent = self
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodePointTextView
        init(_ parent: CodePointTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            report(textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            report(textView)
        }

        /// 選択テキスト（未選択ならカーソル直前の1書記素）を報告する。
        private func report(_ textView: NSTextView) {
            let ns = textView.string as NSString
            let range = textView.selectedRange()
            let selected: String
            if range.length > 0 {
                selected = ns.substring(with: range)
            } else if range.location > 0, range.location <= ns.length {
                let composed = ns.rangeOfComposedCharacterSequence(at: range.location - 1)
                selected = ns.substring(with: composed)
            } else {
                selected = ""
            }
            parent.onSelectionChange(selected)
        }
    }
}
