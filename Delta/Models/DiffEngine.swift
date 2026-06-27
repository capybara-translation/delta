import Foundation

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
}
