import SwiftUI

struct DiffResultView: View {
    let segments: [DiffSegment]
    let mode: DiffMode

    var body: some View {
        ScrollView {
            Group {
                switch mode {
                case .line:
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                            Text(segment.text.isEmpty ? " " : segment.text)
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(background(for: segment.kind))
                        }
                    }
                case .character:
                    Text(attributedText)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func background(for kind: DiffKind) -> Color {
        switch kind {
        case .equal: return .clear
        case .insert: return .green.opacity(0.3)
        case .delete: return .red.opacity(0.3)
        }
    }

    private var attributedText: AttributedString {
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
