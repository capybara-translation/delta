enum DiffMode: Hashable {
    case line
    case character
}

enum DiffKind: Equatable {
    case equal
    case insert
    case delete
}

struct DiffSegment: Equatable {
    let kind: DiffKind
    let text: String
}

struct DiffRow: Equatable {
    let left: [DiffSegment]?    // nil = この行は左に存在しない（ギャップ）
    let right: [DiffSegment]?   // nil = この行は右に存在しない（ギャップ）
}

enum DiffEngine {
    static func diff(_ textA: String, _ textB: String, mode: DiffMode) -> [DiffSegment] {
        let a = tokenize(textA, mode: mode)
        let b = tokenize(textB, mode: mode)
        return align(a, b)
    }

    /// 行モードは改行を維持するため空サブシーケンスを残す。
    /// 文字モードは書記素クラスタ（Swift Character）単位でトークン化する。
    static func tokenize(_ text: String, mode: DiffMode) -> [String] {
        switch mode {
        case .line:
            return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        case .character:
            return text.map(String.init)
        }
    }

    /// CollectionDifference の removals/insertions から、
    /// 削除→挿入→共通の順で 1 列のユニファイドなセグメント列を再構成する。
    static func align(_ a: [String], _ b: [String]) -> [DiffSegment] {
        let difference = b.difference(from: a)
        var removedOffsets = Set<Int>()
        var insertedOffsets = Set<Int>()
        for change in difference {
            switch change {
            case let .remove(offset, _, _): removedOffsets.insert(offset)
            case let .insert(offset, _, _): insertedOffsets.insert(offset)
            }
        }

        var segments: [DiffSegment] = []
        var i = 0
        var j = 0
        while i < a.count || j < b.count {
            if i < a.count, removedOffsets.contains(i) {
                segments.append(DiffSegment(kind: .delete, text: a[i]))
                i += 1
            } else if j < b.count, insertedOffsets.contains(j) {
                segments.append(DiffSegment(kind: .insert, text: b[j]))
                j += 1
            } else if i < a.count, j < b.count {
                segments.append(DiffSegment(kind: .equal, text: a[i]))
                i += 1
                j += 1
            } else if i < a.count {
                segments.append(DiffSegment(kind: .delete, text: a[i]))
                i += 1
            } else {
                segments.append(DiffSegment(kind: .insert, text: b[j]))
                j += 1
            }
        }
        return segments
    }

    // MARK: - Side-by-side

    /// 行揃えの行ペア列を生成する。
    /// 1. 行 diff（既存）でユニファイドな行セグメント列を得る。
    /// 2. 連続する削除群と直後の挿入群をペアにし、各ペアは文字 diff（既存）で行内ハイライトを付ける。
    ///    余った削除/挿入は片側のみの行にする。
    static func sideBySide(_ textA: String, _ textB: String) -> [DiffRow] {
        let lineSegments = diff(textA, textB, mode: .line)
        var rows: [DiffRow] = []
        var index = 0
        while index < lineSegments.count {
            switch lineSegments[index].kind {
            case .equal:
                let line = lineSegments[index].text
                rows.append(DiffRow(
                    left: [DiffSegment(kind: .equal, text: line)],
                    right: [DiffSegment(kind: .equal, text: line)]
                ))
                index += 1
            case .delete:
                var deletes: [String] = []
                while index < lineSegments.count, lineSegments[index].kind == .delete {
                    deletes.append(lineSegments[index].text)
                    index += 1
                }
                var inserts: [String] = []
                while index < lineSegments.count, lineSegments[index].kind == .insert {
                    inserts.append(lineSegments[index].text)
                    index += 1
                }
                rows.append(contentsOf: pairRows(deletes: deletes, inserts: inserts))
            case .insert:
                var inserts: [String] = []
                while index < lineSegments.count, lineSegments[index].kind == .insert {
                    inserts.append(lineSegments[index].text)
                    index += 1
                }
                rows.append(contentsOf: pairRows(deletes: [], inserts: inserts))
            }
        }
        return rows
    }

    /// 削除行群と挿入行群を index 順にペアリングする。
    /// ペアは文字 diff で行内ハイライト、余りは片側のみの行。
    private static func pairRows(deletes: [String], inserts: [String]) -> [DiffRow] {
        var rows: [DiffRow] = []
        let pairCount = min(deletes.count, inserts.count)
        for k in 0..<pairCount {
            let charDiff = diff(deletes[k], inserts[k], mode: .character)
            let leftCell = charDiff.filter { $0.kind != .insert }   // equal + delete
            let rightCell = charDiff.filter { $0.kind != .delete }  // equal + insert
            rows.append(DiffRow(left: leftCell, right: rightCell))
        }
        for k in pairCount..<deletes.count {
            rows.append(DiffRow(left: [DiffSegment(kind: .delete, text: deletes[k])], right: nil))
        }
        for k in pairCount..<inserts.count {
            rows.append(DiffRow(left: nil, right: [DiffSegment(kind: .insert, text: inserts[k])]))
        }
        return rows
    }
}
