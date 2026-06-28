import SwiftUI

struct DiffEditorView: View {
    @Binding var textA: String
    @Binding var textB: String
    @State private var infoA: String = ""
    @State private var infoB: String = ""
    @State private var focusLink = FocusLink()

    var body: some View {
        HStack(spacing: 8) {
            editor("A", field: .a, text: $textA, info: $infoA)
            editor("B", field: .b, text: $textB, info: $infoB)
        }
    }

    private func editor(_ label: String, field: EditorField, text: Binding<String>, info: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            CodePointTextView(text: text, field: field, focusLink: focusLink) { selected in
                info.wrappedValue = CodePointFormatter.describe(selected)
            }

            Text(info.wrappedValue.isEmpty ? " " : info.wrappedValue)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }
}
