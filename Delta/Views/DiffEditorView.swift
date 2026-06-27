import SwiftUI

struct DiffEditorView: View {
    @Binding var textA: String
    @Binding var textB: String

    var body: some View {
        HStack(spacing: 8) {
            editor("A", text: $textA)
            editor("B", text: $textB)
        }
    }

    private func editor(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: text)
                .font(.system(.body, design: .monospaced))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.3))
                )
        }
    }
}
