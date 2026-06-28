import SwiftUI
import AppKit

enum EditorField {
    case a
    case b
}

/// A/B 欄が互いの NSView を見つけるための共有ホルダ。weak 参照で循環を作らない。
final class FocusLink {
    weak var viewA: NSView?
    weak var viewB: NSView?

    func register(_ view: NSView, as field: EditorField) {
        switch field {
        case .a: viewA = view
        case .b: viewB = view
        }
    }

    /// 指定欄の相手をファーストレスポンダにする。相手が無ければ何もしない。
    func focusSibling(of field: EditorField) {
        let target: NSView? = (field == .a) ? viewB : viewA
        guard let target else { return }
        target.window?.makeFirstResponder(target)
    }
}

/// Tab/Shift+Tab を兄弟欄へのフォーカス移動に、Ctrl+Tab をタブ文字入力に振り替える
/// NSTextView。IME 変換中（未確定文字あり）の Tab は横取りしない。
final class NavigatingTextView: NSTextView {
    var onFocusSibling: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if hasMarkedText() {
            super.keyDown(with: event)
            return
        }
        switch TabKeyResolver.action(
            keyCode: event.keyCode,
            hasControl: event.modifierFlags.contains(.control)
        ) {
        case .insertTab:
            insertText("\t", replacementRange: selectedRange)
        case .focusSibling:
            onFocusSibling?()
        case .passThrough:
            super.keyDown(with: event)
        }
    }
}

/// NSTextView をラップした入力欄。text を双方向同期し、選択（未選択ならカーソル直前の
/// 1書記素）を onSelectionChange で報告する。Tab で兄弟欄へフォーカス移動する。
struct CodePointTextView: NSViewRepresentable {
    @Binding var text: String
    let field: EditorField
    let focusLink: FocusLink
    var onSelectionChange: (String) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NavigatingTextView()
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

        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scroll.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )

        scroll.borderType = .bezelBorder

        focusLink.register(textView, as: field)
        textView.onFocusSibling = { [focusLink, field] in
            focusLink.focusSibling(of: field)
        }

        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // 最新のクロージャ/バインディングを Coordinator に反映する。
        context.coordinator.parent = self
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            // 注: text を外部から（ユーザー入力以外で）変更する機能を足す場合、ここでの
            // string 代入が選択変更通知を同期発火し report() → @State 書き込みが
            // ビュー更新中に走り得る。その際は report() を再入ガード/遅延する。
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
            let range = textView.selectedRange
            let selected: String
            if range.length > 0, NSMaxRange(range) <= ns.length {
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
