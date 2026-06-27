import SwiftUI

/// side-by-side の1セル。nil はギャップ（行なし）。
/// 行全体の追加/削除はセル全幅を塗り、行内ハイライトは変更文字レンジのみ塗る。
struct DiffCellView: View {
    let segments: [DiffSegment]?

    var body: some View {
        Text(displayText)
            .font(.system(.body, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fullWidthBackground)
            .textSelection(.enabled)
    }

    private var fullWidthBackground: Color {
        guard let segments else { return .gray.opacity(0.08) }   // ギャップ（行なし）
        if segments.count == 1 {
            switch segments[0].kind {
            case .insert: return .green.opacity(0.3)              // 行全体追加
            case .delete: return .red.opacity(0.3)               // 行全体削除
            case .equal: return .clear
            }
        }
        return .clear                                            // 行内ハイライト or 共通
    }

    private var displayText: AttributedString {
        guard let segments else { return AttributedString(" ") } // ギャップ
        let joined = segments.map(\.text).joined()
        if joined.isEmpty { return AttributedString(" ") }       // 空行の高さ確保
        // 行全体の追加/削除は fullWidthBackground が塗るので素のテキスト。
        if segments.count == 1, segments[0].kind != .equal {
            return AttributedString(joined)
        }
        // 行内ハイライト: 変更文字レンジにのみ背景色。
        var result = AttributedString()
        for segment in segments {
            var piece = AttributedString(segment.text)
            switch segment.kind {
            case .equal: break
            case .insert: piece.backgroundColor = .green.opacity(0.3)
            case .delete: piece.backgroundColor = .red.opacity(0.3)
            }
            result.append(piece)
        }
        return result
    }
}
