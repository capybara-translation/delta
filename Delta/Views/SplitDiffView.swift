import SwiftUI

enum SplitOrientation: String {
    case horizontal
    case vertical
}

/// 行揃えの side-by-side 表示。
/// horizontal: 各行を HStack(左セル, 仕切り, 右セル) で並べ、行内で高さが揃うため折り返しても整列する。
/// vertical: 左ペイン（全行の左セル）を上、右ペインを下に積む。
struct SplitDiffView: View {
    let rows: [DiffRow]
    let orientation: SplitOrientation

    var body: some View {
        ScrollView {
            switch orientation {
            case .horizontal:
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .top, spacing: 0) {
                            DiffCellView(segments: row.left)
                            Divider()
                            DiffCellView(segments: row.right)
                        }
                    }
                }
            case .vertical:
                VStack(spacing: 0) {
                    pane { $0.left }
                    Divider()
                    pane { $0.right }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func pane(_ side: @escaping (DiffRow) -> [DiffSegment]?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                DiffCellView(segments: side(row))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
