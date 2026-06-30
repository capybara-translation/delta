// DeltaTests/HotKeyConfigTests.swift
import Testing
import Carbon
@testable import Delta

struct HotKeyConfigTests {
    @Test func defaultIsControlOptionD() {
        let d = HotKeyConfig.default
        #expect(d.keyCode == UInt32(kVK_ANSI_D))
        #expect(d.modifiers == UInt32(controlKey | optionKey))
        #expect(d.isEnabled)
        #expect(d.displayString == "⌃⌥D")
    }

    @Test func requiresCmdCtrlOrOpt() {
        #expect(HotKeyConfig(keyCode: 0, modifiers: UInt32(controlKey), isEnabled: true).hasRequiredModifier)
        #expect(HotKeyConfig(keyCode: 0, modifiers: UInt32(cmdKey), isEnabled: true).hasRequiredModifier)
        #expect(HotKeyConfig(keyCode: 0, modifiers: UInt32(optionKey), isEnabled: true).hasRequiredModifier)
        // shift-only and none are not enough
        #expect(!HotKeyConfig(keyCode: 0, modifiers: UInt32(shiftKey), isEnabled: true).hasRequiredModifier)
        #expect(!HotKeyConfig(keyCode: 0, modifiers: 0, isEnabled: true).hasRequiredModifier)
    }
}
