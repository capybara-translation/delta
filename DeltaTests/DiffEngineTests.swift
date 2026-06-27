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
}
