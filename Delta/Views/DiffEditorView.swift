import SwiftUI
import AppKit

struct DiffEditorView: View {
    @Binding var textA: String
    @Binding var textB: String
    @State private var selectionA: String = ""
    @State private var selectionB: String = ""
    @State private var focusLink = FocusLink()

    var body: some View {
        HStack(spacing: 8) {
            editor("A", field: .a, text: $textA, selection: $selectionA)
            editor("B", field: .b, text: $textB, selection: $selectionB)
        }
    }

    private func editor(_ label: String, field: EditorField, text: Binding<String>, selection: Binding<String>) -> some View {
        // Display keeps the existing truncation; the copy action uses the full list.
        let display = CodePointFormatter.describe(selection.wrappedValue)
        return VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            CodePointTextView(text: text, field: field, focusLink: focusLink) { selected in
                selection.wrappedValue = selected
            }

            // Note: no .textSelection here. A selectable Text hijacks right-click
            // with the system text menu, which hides our .contextMenu. Since the
            // context menu provides the full-copy action, we drop text selection.
            Text(display.isEmpty ? " " : display)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contextMenu {
                    Button("Copy code points") {
                        copyCodePoints(selection.wrappedValue)
                    }
                    .disabled(selection.wrappedValue.isEmpty)
                }
        }
    }

    private func copyCodePoints(_ selected: String) {
        // Guard here (not only via .disabled) so correctness doesn't depend on the
        // menu's disabled state, which is derived from NSTextView focus/selection.
        guard !selected.isEmpty else { return }
        let full = CodePointFormatter.fullList(selected)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(full, forType: .string)
    }
}
