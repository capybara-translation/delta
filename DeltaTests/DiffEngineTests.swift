import Testing
@testable import Delta

struct DiffEngineTests {
    @Test func lineEqual() {
        let r = DiffEngine.diff("a\nb", "a\nb", mode: .line)
        #expect(r == [
            DiffSegment(kind: .equal, text: "a"),
            DiffSegment(kind: .equal, text: "b"),
        ])
    }

    @Test func lineInsert() {
        let r = DiffEngine.diff("a", "a\nb", mode: .line)
        #expect(r == [
            DiffSegment(kind: .equal, text: "a"),
            DiffSegment(kind: .insert, text: "b"),
        ])
    }

    @Test func lineDelete() {
        let r = DiffEngine.diff("a\nb", "a", mode: .line)
        #expect(r == [
            DiffSegment(kind: .equal, text: "a"),
            DiffSegment(kind: .delete, text: "b"),
        ])
    }

    @Test func lineReplace() {
        let r = DiffEngine.diff("a\nb", "a\nc", mode: .line)
        #expect(r == [
            DiffSegment(kind: .equal, text: "a"),
            DiffSegment(kind: .delete, text: "b"),
            DiffSegment(kind: .insert, text: "c"),
        ])
    }

    @Test func lineTrailingNewline() {
        // "a\n" -> ["a", ""], "a" -> ["a"]
        let r = DiffEngine.diff("a\n", "a", mode: .line)
        #expect(r == [
            DiffSegment(kind: .equal, text: "a"),
            DiffSegment(kind: .delete, text: ""),
        ])
    }

    @Test func bothEmptyLine() {
        let r = DiffEngine.diff("", "", mode: .line)
        #expect(r == [DiffSegment(kind: .equal, text: "")])
    }

    @Test func japaneseCharReplace() {
        let r = DiffEngine.diff("色赤", "色青", mode: .character)
        #expect(r == [
            DiffSegment(kind: .equal, text: "色"),
            DiffSegment(kind: .delete, text: "赤"),
            DiffSegment(kind: .insert, text: "青"),
        ])
    }

    @Test func japaneseCharInsert() {
        let r = DiffEngine.diff("あい", "あxい", mode: .character)
        #expect(r == [
            DiffSegment(kind: .equal, text: "あ"),
            DiffSegment(kind: .insert, text: "x"),
            DiffSegment(kind: .equal, text: "い"),
        ])
    }

    @Test func emojiGraphemeReplace() {
        let r = DiffEngine.diff("👍", "👎", mode: .character)
        #expect(r == [
            DiffSegment(kind: .delete, text: "👍"),
            DiffSegment(kind: .insert, text: "👎"),
        ])
    }

    @Test func bothEmptyChar() {
        let r = DiffEngine.diff("", "", mode: .character)
        #expect(r == [])
    }

    @Test func largeInputDoesNotCrash() {
        let a = String(repeating: "x\n", count: 2000)
        let b = a + "y"
        let r = DiffEngine.diff(a, b, mode: .line)
        #expect(!r.isEmpty)
    }

    @Test func lineMultiEditReplace() {
        let r = DiffEngine.diff("a\nb\nc", "a\nx\nc", mode: .line)
        #expect(r == [
            DiffSegment(kind: .equal, text: "a"),
            DiffSegment(kind: .delete, text: "b"),
            DiffSegment(kind: .insert, text: "x"),
            DiffSegment(kind: .equal, text: "c"),
        ])
    }

    @Test func lineEmptyToNonEmpty() {
        // "" -> [""], "a\nb" -> ["a", "b"]; no common element with "",
        // so the empty token is deleted and both lines inserted.
        let r = DiffEngine.diff("", "a\nb", mode: .line)
        #expect(r == [
            DiffSegment(kind: .delete, text: ""),
            DiffSegment(kind: .insert, text: "a"),
            DiffSegment(kind: .insert, text: "b"),
        ])
    }

    // MARK: - sideBySide

    @Test func sideBySideAllEqual() {
        let r = DiffEngine.sideBySide("a\nb", "a\nb")
        #expect(r == [
            DiffRow(left: [DiffSegment(kind: .equal, text: "a")], right: [DiffSegment(kind: .equal, text: "a")]),
            DiffRow(left: [DiffSegment(kind: .equal, text: "b")], right: [DiffSegment(kind: .equal, text: "b")]),
        ])
    }

    @Test func sideBySidePureInsert() {
        let r = DiffEngine.sideBySide("a", "a\nb")
        #expect(r == [
            DiffRow(left: [DiffSegment(kind: .equal, text: "a")], right: [DiffSegment(kind: .equal, text: "a")]),
            DiffRow(left: nil, right: [DiffSegment(kind: .insert, text: "b")]),
        ])
    }

    @Test func sideBySidePureDelete() {
        let r = DiffEngine.sideBySide("a\nb", "a")
        #expect(r == [
            DiffRow(left: [DiffSegment(kind: .equal, text: "a")], right: [DiffSegment(kind: .equal, text: "a")]),
            DiffRow(left: [DiffSegment(kind: .delete, text: "b")], right: nil),
        ])
    }

    @Test func sideBySideIntralineReplace() {
        let r = DiffEngine.sideBySide("色赤", "色青")
        #expect(r == [
            DiffRow(
                left: [DiffSegment(kind: .equal, text: "色"), DiffSegment(kind: .delete, text: "赤")],
                right: [DiffSegment(kind: .equal, text: "色"), DiffSegment(kind: .insert, text: "青")]
            ),
        ])
    }

    @Test func sideBySideMultiLineReplacePairing() {
        let r = DiffEngine.sideBySide("a\nb\nc", "x\ny\nc")
        #expect(r == [
            DiffRow(left: [DiffSegment(kind: .delete, text: "a")], right: [DiffSegment(kind: .insert, text: "x")]),
            DiffRow(left: [DiffSegment(kind: .delete, text: "b")], right: [DiffSegment(kind: .insert, text: "y")]),
            DiffRow(left: [DiffSegment(kind: .equal, text: "c")], right: [DiffSegment(kind: .equal, text: "c")]),
        ])
    }

    @Test func sideBySideMoreDeletesThanInserts() {
        // A=["a","b","c"], B=["x"]; line diff: [del a, del b, del c, ins x]
        let r = DiffEngine.sideBySide("a\nb\nc", "x")
        #expect(r == [
            DiffRow(left: [DiffSegment(kind: .delete, text: "a")], right: [DiffSegment(kind: .insert, text: "x")]),
            DiffRow(left: [DiffSegment(kind: .delete, text: "b")], right: nil),
            DiffRow(left: [DiffSegment(kind: .delete, text: "c")], right: nil),
        ])
    }

    @Test func sideBySideMoreInsertsThanDeletes() {
        // A=["a"], B=["x","y","z"]; line diff: [del a, ins x, ins y, ins z]
        let r = DiffEngine.sideBySide("a", "x\ny\nz")
        #expect(r == [
            DiffRow(left: [DiffSegment(kind: .delete, text: "a")], right: [DiffSegment(kind: .insert, text: "x")]),
            DiffRow(left: nil, right: [DiffSegment(kind: .insert, text: "y")]),
            DiffRow(left: nil, right: [DiffSegment(kind: .insert, text: "z")]),
        ])
    }

    @Test func sideBySideTrailingNewline() {
        // "a\n"->["a",""], "a"->["a"]; line diff: [equal a, delete ""]
        let r = DiffEngine.sideBySide("a\n", "a")
        #expect(r == [
            DiffRow(left: [DiffSegment(kind: .equal, text: "a")], right: [DiffSegment(kind: .equal, text: "a")]),
            DiffRow(left: [DiffSegment(kind: .delete, text: "")], right: nil),
        ])
    }

    @Test func sideBySideBothEmpty() {
        let r = DiffEngine.sideBySide("", "")
        #expect(r == [
            DiffRow(left: [DiffSegment(kind: .equal, text: "")], right: [DiffSegment(kind: .equal, text: "")]),
        ])
    }

    // MARK: - Scalar-sensitive (encoding difference detection)

    @Test func characterDiffDetectsNFCvsNFD() {
        // NFC "ờ" = U+1EDD (1 scalar), NFD "ờ" = U+006F U+031B U+0300 (3 scalars).
        // They are canonically equivalent but encoded differently, so scalar comparison produces a diff.
        let nfc = "\u{1EDD}"
        let nfd = "\u{006F}\u{031B}\u{0300}"
        let r = DiffEngine.diff(nfc, nfd, mode: .character)
        #expect(r == [
            DiffSegment(kind: .delete, text: nfc),
            DiffSegment(kind: .insert, text: nfd),
        ])
    }

    @Test func sideBySideDetectsNFCvsNFD() {
        // Only the encoding of "ờ" differs within the line. The line is detected as changed (encoding-sensitive), and "ờ" is highlighted intra-line.
        let nfc = "\u{1EDD}"
        let nfd = "\u{006F}\u{031B}\u{0300}"
        let r = DiffEngine.sideBySide("A" + nfc + "B", "A" + nfd + "B")
        #expect(r == [
            DiffRow(
                left: [
                    DiffSegment(kind: .equal, text: "A"),
                    DiffSegment(kind: .delete, text: nfc),
                    DiffSegment(kind: .equal, text: "B"),
                ],
                right: [
                    DiffSegment(kind: .equal, text: "A"),
                    DiffSegment(kind: .insert, text: nfd),
                    DiffSegment(kind: .equal, text: "B"),
                ]
            ),
        ])
    }

    @Test func identicalScalarsStillEqual() {
        // Identical scalar sequences continue to produce no diff (regression check).
        let r = DiffEngine.diff("abc", "abc", mode: .character)
        #expect(r == [
            DiffSegment(kind: .equal, text: "a"),
            DiffSegment(kind: .equal, text: "b"),
            DiffSegment(kind: .equal, text: "c"),
        ])
    }
}
