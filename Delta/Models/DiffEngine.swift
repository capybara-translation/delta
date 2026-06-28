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
    let left: [DiffSegment]?    // nil = this row does not exist on the left (gap)
    let right: [DiffSegment]?   // nil = this row does not exist on the right (gap)
}

/// Token that compares by Unicode scalar sequence rather than canonical equivalence.
/// Swift's String/Character == uses canonical equivalence and cannot distinguish NFC/NFD etc.
/// Diff detection uses this token's == / hash (scalar-based).
private struct ExactToken: Hashable {
    let text: String
    static func == (lhs: ExactToken, rhs: ExactToken) -> Bool {
        lhs.text.unicodeScalars.elementsEqual(rhs.text.unicodeScalars)
    }
    func hash(into hasher: inout Hasher) {
        for scalar in text.unicodeScalars { hasher.combine(scalar.value) }
    }
}

enum DiffEngine {
    static func diff(_ textA: String, _ textB: String, mode: DiffMode) -> [DiffSegment] {
        let a = tokenize(textA, mode: mode)
        let b = tokenize(textB, mode: mode)
        return align(a, b)
    }

    /// Line mode retains empty subsequences to preserve newlines.
    /// Character mode tokenizes by grapheme cluster (Swift Character).
    /// Comparison is performed by ExactToken via Unicode scalar sequence (not canonical equivalence).
    private static func tokenize(_ text: String, mode: DiffMode) -> [ExactToken] {
        switch mode {
        case .line:
            return text.split(separator: "\n", omittingEmptySubsequences: false)
                .map { ExactToken(text: String($0)) }
        case .character:
            return text.map { ExactToken(text: String($0)) }
        }
    }

    /// Reconstructs a unified segment list in delete→insert→equal order
    /// from CollectionDifference's removals/insertions.
    ///
    /// Invariant: within a change block, deletions always appear before insertions (because
    /// the delete branch is checked before the insert branch). `sideBySide` relies on this
    /// ordering to pair deletions with insertions — do not change the branch order.
    private static func align(_ a: [ExactToken], _ b: [ExactToken]) -> [DiffSegment] {
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
                segments.append(DiffSegment(kind: .delete, text: a[i].text))
                i += 1
            } else if j < b.count, insertedOffsets.contains(j) {
                segments.append(DiffSegment(kind: .insert, text: b[j].text))
                j += 1
            } else if i < a.count, j < b.count {
                segments.append(DiffSegment(kind: .equal, text: a[i].text))
                i += 1
                j += 1
            } else if i < a.count {
                segments.append(DiffSegment(kind: .delete, text: a[i].text))
                i += 1
            } else {
                segments.append(DiffSegment(kind: .insert, text: b[j].text))
                j += 1
            }
        }
        return segments
    }

    // MARK: - Side-by-side

    /// Produces the line-pair sequence for line-aligned display.
    /// 1. Obtains a unified line-segment list via the existing line diff.
    /// 2. Pairs each run of consecutive deletions with the immediately following insertions; each pair
    ///    receives intra-line highlights via the existing character diff. Leftover deletions/insertions become single-sided rows.
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

    /// Pairs the group of deleted lines with the group of inserted lines in index order.
    /// Paired lines receive intra-line highlights via character diff; extras become single-sided rows.
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
