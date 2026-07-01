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

            Text(display.isEmpty ? " " : display)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .contextMenu {
                    Button("Copy code points") {
                        copyCodePoints(selection.wrappedValue)
                    }
                    .disabled(selection.wrappedValue.isEmpty)
                }
        }
    }

    private func copyCodePoints(_ selected: String) {
        let full = CodePointFormatter.fullList(selected)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(full, forType: .string)
    }
}
