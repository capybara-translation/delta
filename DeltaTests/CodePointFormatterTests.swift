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
        // NFC "ờ" = U+1EDD (1 scalar) → name appended
        #expect(CodePointFormatter.describe("\u{1EDD}") == "U+1EDD LATIN SMALL LETTER O WITH HORN AND GRAVE")
    }

    @Test func nfdVietnameseListsScalars() {
        // NFD "ờ" = o + combining horn + combining grave (3 scalars) → no name
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
        // U+1F600 has a 5-digit hex code. One scalar, so the name is appended.
        #expect(CodePointFormatter.describe("\u{1F600}") == "U+1F600 GRINNING FACE")
    }

    @Test func controlScalarHasNoName() {
        // U+0001 is a control character with no name → code point only.
        #expect(CodePointFormatter.describe("\u{0001}") == "U+0001")
    }

    @Test func exactlyMaxScalarsHasNoOverflowSuffix() {
        // Exactly 24 scalars should not produce a truncation suffix.
        let r = CodePointFormatter.describe(String(repeating: "a", count: 24))
        let expected = Array(repeating: "U+0061", count: 24).joined(separator: " ")
        #expect(r == expected)
    }

    @Test func fullListEmptyIsEmpty() {
        #expect(CodePointFormatter.fullList("") == "")
    }

    @Test func fullListSingleHasName() {
        #expect(CodePointFormatter.fullList("A") == "U+0041 LATIN CAPITAL LETTER A")
    }

    @Test func fullListMultipleHasNoName() {
        #expect(CodePointFormatter.fullList("AB") == "U+0041 U+0042")
    }

    @Test func fullListSingleNamelessScalar() {
        // U+0001 is a control character with no Unicode name → code point only.
        #expect(CodePointFormatter.fullList("\u{0001}") == "U+0001")
    }

    @Test func fullListDoesNotTruncateBeyondMax() {
        // 30 scalars exceeds maxScalars (24). fullList must contain all 30 and no
        // truncation marker, whereas describe truncates the same input.
        let input = String(repeating: "a", count: 30)
        let full = CodePointFormatter.fullList(input)
        let expected = Array(repeating: "U+0061", count: 30).joined(separator: " ")
        #expect(full == expected)
        #expect(!full.contains("…"))
        #expect(CodePointFormatter.describe(input).contains("… (+"))
    }
}
