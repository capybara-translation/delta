import Testing
import AppKit
import Carbon
@testable import Delta

struct KeyCodeFormatterTests {
    @Test func modifierSymbolsUseAppleOrder() {
        let all = UInt32(controlKey | optionKey | shiftKey | cmdKey)
        #expect(KeyCodeFormatter.modifierSymbols(all) == "⌃⌥⇧⌘")
        #expect(KeyCodeFormatter.modifierSymbols(UInt32(controlKey | optionKey)) == "⌃⌥")
    }

    @Test func stringCombinesModifiersAndKey() {
        let s = KeyCodeFormatter.string(keyCode: UInt32(kVK_ANSI_D),
                                        modifiers: UInt32(controlKey | optionKey))
        #expect(s == "⌃⌥D")
    }

    @Test func keyStringNamesSpecialKeys() {
        #expect(KeyCodeFormatter.keyString(UInt32(kVK_Space)) == "Space")
        #expect(KeyCodeFormatter.keyString(UInt32(kVK_Return)) == "↩")
        #expect(KeyCodeFormatter.keyString(UInt32(kVK_ANSI_A)) == "A")
    }

    @Test func carbonAndEventFlagsRoundTrip() {
        let flags: NSEvent.ModifierFlags = [.control, .option]
        let carbon = KeyCodeFormatter.carbonFlags(from: flags)
        #expect(carbon == UInt32(controlKey | optionKey))
        let back = KeyCodeFormatter.modifierFlags(from: carbon)
        #expect(back.contains(.control))
        #expect(back.contains(.option))
        #expect(!back.contains(.command))
    }
}
