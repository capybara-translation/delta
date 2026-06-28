import SwiftUI

/// One cell in the side-by-side view. nil means a gap (no corresponding row).
/// Whole-line additions/deletions fill the full cell width; intra-line highlights color only the changed character ranges.
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
        guard let segments else { return .gray.opacity(0.08) }   // gap (no row)
        if segments.count == 1 {
            switch segments[0].kind {
            case .insert: return .green.opacity(0.3)              // whole-line addition
            case .delete: return .red.opacity(0.3)               // whole-line deletion
            case .equal: return .clear
            }
        }
        return .clear                                            // intra-line highlight or common
    }

    private var displayText: AttributedString {
        guard let segments else { return AttributedString(" ") } // gap
        let joined = segments.map(\.text).joined()
        if joined.isEmpty { return AttributedString(" ") }       // preserve height for empty lines
        // Whole-line additions/deletions are colored by fullWidthBackground, so use plain text.
        if segments.count == 1, segments[0].kind != .equal {
            return AttributedString(joined)
        }
        // Intra-line highlight: apply background color only to changed character ranges.
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
