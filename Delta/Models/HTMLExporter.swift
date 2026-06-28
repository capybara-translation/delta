import Foundation

/// Generates a self-contained HTML document for a diff result, following the given orientation.
enum HTMLExporter {
    static func html(rows: [DiffRow], orientation: SplitOrientation, generatedAt: Date) -> String {
        let body: String
        switch orientation {
        case .horizontal:
            let trs = rows.map { "<tr>\(cell($0.left))\(cell($0.right))</tr>" }.joined(separator: "\n")
            body = "<table class=\"diff h\">\n\(trs)\n</table>"
        case .vertical:
            let left = rows.map { lineDiv($0.left) }.joined(separator: "\n")
            let right = rows.map { lineDiv($0.right) }.joined(separator: "\n")
            body = "<div class=\"diff v\">\n<div class=\"pane\">\n\(left)\n</div>\n<div class=\"pane\">\n\(right)\n</div>\n</div>"
        }

        let meta = "Generated: " + ISO8601DateFormatter().string(from: generatedAt)

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <title>Delta Diff</title>
        <style>
        body { font-family: ui-monospace, Menlo, monospace; margin: 16px; }
        .meta { color: #666; font-size: 12px; margin-bottom: 12px; }
        table.diff { border-collapse: collapse; width: 100%; }
        table.diff td { vertical-align: top; width: 50%; padding: 0 6px; border-left: 1px solid #ddd; white-space: pre; }
        .pane { border-bottom: 1px solid #ddd; padding: 6px 0; }
        .line { white-space: pre; }
        .ins { background: #ccffd8; }
        .del { background: #ffd7d5; }
        .gap { background: #f0f0f0; }
        </style>
        </head>
        <body>
        <p class="meta">\(escape(meta))</p>
        \(body)
        </body>
        </html>
        """
    }

    /// Table cell (horizontal). nil = gap.
    private static func cell(_ segments: [DiffSegment]?) -> String {
        guard let segments else { return "<td class=\"gap\">\(nbsp)</td>" }
        let (cls, inner) = render(segments)
        let classAttr = cls.isEmpty ? "" : " class=\"\(cls)\""
        return "<td\(classAttr)>\(inner)</td>"
    }

    /// Line in a vertical pane. nil = gap.
    private static func lineDiv(_ segments: [DiffSegment]?) -> String {
        guard let segments else { return "<div class=\"line gap\">\(nbsp)</div>" }
        let (cls, inner) = render(segments)
        let classAttr = cls.isEmpty ? "line" : "line \(cls)"
        return "<div class=\"\(classAttr)\">\(inner)</div>"
    }

    /// Returns (whole-line background class, inner HTML).
    /// A single non-equal segment colors the whole cell; otherwise changed runs are wrapped in spans.
    private static func render(_ segments: [DiffSegment]) -> (String, String) {
        let joined = segments.map(\.text).joined()
        if joined.isEmpty { return ("", nbsp) }
        if segments.count == 1, segments[0].kind != .equal {
            return (segments[0].kind == .insert ? "ins" : "del", escape(joined))
        }
        let inner = segments.map { seg -> String in
            let t = escape(seg.text)
            switch seg.kind {
            case .equal: return t
            case .insert: return "<span class=\"ins\">\(t)</span>"
            case .delete: return "<span class=\"del\">\(t)</span>"
            }
        }.joined()
        return ("", inner)
    }

    private static let nbsp = "&nbsp;"

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
