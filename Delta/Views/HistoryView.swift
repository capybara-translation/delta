import SwiftUI

/// Popover content listing recent comparisons. Selecting an entry calls onSelect; Clear empties the store.
struct HistoryView: View {
    let store: HistoryStore
    var onSelect: (HistoryEntry) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("History").font(.headline)
                Spacer()
                Button("Clear") { store.clear() }
                    .disabled(store.entries.isEmpty)
            }
            .padding(8)

            Divider()

            if store.entries.isEmpty {
                Text("No history")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(store.entries) { entry in
                    Button {
                        onSelect(entry)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.timestamp, format: .dateTime.month().day().hour().minute().second())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(preview(entry))
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 360, height: 320)
    }

    private func preview(_ entry: HistoryEntry) -> String {
        // Truncate before building the preview string so multi-MB inputs don't
        // allocate full copies per row; the row is single-line and clipped anyway.
        let a = entry.textA.prefix(200).replacingOccurrences(of: "\n", with: " ")
        let b = entry.textB.prefix(200).replacingOccurrences(of: "\n", with: " ")
        return "A: \(a)  B: \(b)"
    }
}
