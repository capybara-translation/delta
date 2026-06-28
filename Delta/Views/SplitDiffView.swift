import SwiftUI

enum SplitOrientation: String {
    case horizontal
    case vertical
}

/// Line-aligned side-by-side view.
/// horizontal: arranges each row as HStack(left cell, right cell) to equalize height within a row. The divider is
///   overlaid at the center of the result area spanning the full height, extending to the bottom of the screen (independent of row count).
/// vertical: stacks the left pane (all rows' left cells) above the right pane.
struct SplitDiffView: View {
    let rows: [DiffRow]
    let orientation: SplitOrientation

    /// Gutter width around the center divider (keeps text from touching the line).
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
                    // Full-height vertical divider fixed at center (viewport-anchored, does not scroll away).
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
                            .padding(.vertical, centerGutter)
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
