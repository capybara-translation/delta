import SwiftUI
import AppKit

enum EditorField {
    case a
    case b
}

/// Shared holder that lets the A and B fields locate each other's NSView. Uses weak references to avoid retain cycles.
final class FocusLink {
    weak var viewA: NSView?
    weak var viewB: NSView?

    func register(_ view: NSView, as field: EditorField) {
        switch field {
        case .a: viewA = view
        case .b: viewB = view
        }
    }

    /// Makes the sibling of the specified field the first responder. Does nothing if there is no sibling.
    func focusSibling(of field: EditorField) {
        let target: NSView? = (field == .a) ? viewB : viewA
        guard let target else { return }
        target.window?.makeFirstResponder(target)
    }
}

/// An NSTextView that redirects Tab/Shift+Tab to focus-move between sibling fields and Ctrl+Tab to literal tab insertion.
/// Does not intercept Tab while IME composition is active (i.e., when hasMarkedText() returns true).
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

/// An input field wrapping NSTextView. Bidirectionally syncs text and reports the current selection
/// (or the one grapheme cluster before the cursor when nothing is selected) via onSelectionChange. Tab moves focus to the sibling field.
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
        // Propagate the latest closure/binding to the Coordinator.
        context.coordinator.parent = self
        guard let textView = nsView.documentView as? NSTextView else { return }
        // Do not write back while IME composition is active: assigning `string` discards the
        // marked (uncommitted) text and aborts composition, which breaks input when @AppStorage
        // round-trips every keystroke through this update path. Skip until composition commits.
        if textView.string != text, !textView.hasMarkedText() {
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

        /// Reports the selected text, or the one grapheme cluster before the cursor when nothing is selected.
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
