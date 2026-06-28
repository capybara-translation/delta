import SwiftUI

struct DiffWindowView: View {
    @AppStorage("textA") private var textA = ""
    @AppStorage("textB") private var textB = ""
    @AppStorage("splitOrientation") private var orientation: SplitOrientation = .horizontal
    @State private var rows: [DiffRow] = []
    @State private var history = HistoryStore()
    @State private var showingHistory = false

    var body: some View {
        VStack(spacing: 8) {
            DiffEditorView(textA: $textA, textB: $textB)
                .frame(minHeight: 160)

            HStack {
                Picker("", selection: $orientation) {
                    Text("Horizontal").tag(SplitOrientation.horizontal)
                    Text("Vertical").tag(SplitOrientation.vertical)
                }
                .pickerStyle(.segmented)
                .fixedSize()

                Spacer()

                Button("History") { showingHistory.toggle() }
                    .popover(isPresented: $showingHistory, arrowEdge: .bottom) {
                        HistoryView(store: history) { entry in
                            textA = entry.textA
                            textB = entry.textB
                            showingHistory = false
                        }
                    }

                Button("Compare") { run() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
            }

            Divider()

            SplitDiffView(rows: rows, orientation: orientation)
        }
        .padding(12)
        .frame(minWidth: 480, minHeight: 420)
    }

    private func run() {
        rows = DiffEngine.sideBySide(textA, textB)
        history.add(textA: textA, textB: textB, date: Date())
    }
}
