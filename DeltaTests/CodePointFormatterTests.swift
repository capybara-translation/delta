import Testing
@testable import Delta

struct CodePointFormatterTests {
    @Test func emptyIsEmpty() {
        #expect(CodePointFormatter.describe("") == "")
    }

    @Test func singleAsciiHasName() {
        #expect(CodePointFormatter.describe("A") == "U+0041 LATIN CAPITAL LETTER A")
    }

    @Test func singleNFCVietnameseHasName() {
        // NFC「ờ」= U+1EDD（1スカラー）→ 名前併記
        #expect(CodePointFormatter.describe("\u{1EDD}") == "U+1EDD LATIN SMALL LETTER O WITH HORN AND GRAVE")
    }

    @Test func nfdVietnameseListsScalars() {
        // NFD「ờ」= o + 結合ホーン + 結合グレーブ（3スカラー）→ 名前なし
        #expect(CodePointFormatter.describe("\u{006F}\u{031B}\u{0300}") == "U+006F U+031B U+0300")
    }

    @Test func multipleCharactersListScalars() {
        #expect(CodePointFormatter.describe("AB") == "U+0041 U+0042")
    }

    @Test func capsLongSelection() {
        let r = CodePointFormatter.describe(String(repeating: "a", count: 25))
        let expected = Array(repeating: "U+0061", count: 24).joined(separator: " ") + " … (+1)"
        #expect(r == expected)
    }

    @Test func astralScalarHasFiveDigitHexAndName() {
        // U+1F600 は5桁16進。1スカラーなので名前併記。
        #expect(CodePointFormatter.describe("\u{1F600}") == "U+1F600 GRINNING FACE")
    }

    @Test func controlScalarHasNoName() {
        // U+0001 は名前を持たない制御文字 → コードポイントのみ。
        #expect(CodePointFormatter.describe("\u{0001}") == "U+0001")
    }

    @Test func exactlyMaxScalarsHasNoOverflowSuffix() {
        // ちょうど24スカラーは打ち切りサフィックスを付けない。
        let r = CodePointFormatter.describe(String(repeating: "a", count: 24))
        let expected = Array(repeating: "U+0061", count: 24).joined(separator: " ")
        #expect(r == expected)
    }
}
