import SwiftUI

enum SplitOrientation: String {
    case horizontal
    case vertical
}

/// 行揃えの side-by-side 表示。
/// horizontal: 各行を HStack(左セル, 右セル) で並べ行内で高さを揃える。区切り線は
///   結果領域の中央に全高でオーバーレイし、画面下端まで伸ばす（行数に依存しない）。
/// vertical: 左ペイン（全行の左セル）を上、右ペインを下に積む。
struct SplitDiffView: View {
    let rows: [DiffRow]
    let orientation: SplitOrientation

    /// 中央区切り線まわりのガター幅（テキストが線に接しないようにする）。
    private let centerGutter: CGFloat = 6

    var body: some View {
        Group {
            switch orientation {
            case .horizontal:
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            HStack(alignment: .top, spacing: 0) {
                                DiffCellView(segments: row.left)
                                    .padding(.trailing, centerGutter)
                                DiffCellView(segments: row.right)
                                    .padding(.leading, centerGutter)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .overlay {
                    // 中央に全高の縦区切り線（ビューポートに固定、スクロールしても途切れない）。
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Divider()
                        Spacer(minLength: 0)
                    }
                }
            case .vertical:
                ScrollView {
                    VStack(spacing: 0) {
                        pane { $0.left }
                        Divider()
                        pane { $0.right }
                    }
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
