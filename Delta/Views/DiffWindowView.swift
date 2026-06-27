import SwiftUI

struct DiffWindowView: View {
    @State private var textA = ""
    @State private var textB = ""
    @AppStorage("splitOrientation") private var orientation: SplitOrientation = .horizontal
    @State private var rows: [DiffRow] = []

    var body: some View {
        VStack(spacing: 8) {
            DiffEditorView(textA: $textA, textB: $textB)
                .frame(minHeight: 160)

            HStack {
                Picker("", selection: $orientation) {
                    Text("左右").tag(SplitOrientation.horizontal)
                    Text("上下").tag(SplitOrientation.vertical)
                }
                .pickerStyle(.segmented)
                .fixedSize()

                Spacer()

                Button("実行") { run() }
                    .keyboardShortcut(.return, modifiers: .command)
            }

            Divider()

            SplitDiffView(rows: rows, orientation: orientation)
        }
        .padding(12)
        .frame(minWidth: 480, minHeight: 420)
    }

    private func run() {
        rows = DiffEngine.sideBySide(textA, textB)
    }
}
