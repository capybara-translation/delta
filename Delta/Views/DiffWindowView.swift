import SwiftUI

struct DiffWindowView: View {
    @State private var textA = ""
    @State private var textB = ""
    @State private var mode: DiffMode = .line
    @State private var result: [DiffSegment] = []

    var body: some View {
        VStack(spacing: 8) {
            DiffEditorView(textA: $textA, textB: $textB)
                .frame(minHeight: 160)

            HStack {
                Picker("", selection: $mode) {
                    Text("行").tag(DiffMode.line)
                    Text("文字").tag(DiffMode.character)
                }
                .pickerStyle(.segmented)
                .fixedSize()

                Spacer()

                Button("実行") { run() }
                    .keyboardShortcut(.return, modifiers: .command)
            }

            Divider()

            DiffResultView(segments: result, mode: mode)
        }
        .padding(12)
        .frame(minWidth: 480, minHeight: 420)
    }

    private func run() {
        result = DiffEngine.diff(textA, textB, mode: mode)
    }
}
