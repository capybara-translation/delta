import Testing
import Carbon
@testable import Delta

@MainActor
struct HotKeyControllerTests {
    /// An enabled binding without a required modifier (⌘/⌃/⌥) must be rejected by
    /// `apply` before it can reach Carbon — registering a modifier-less hotkey
    /// would swallow every press of that key system-wide. The rejection path
    /// returns early (no state change, no persistence, no registration), so this
    /// is safe to run against the shared controller without touching the live
    /// hotkey or UserDefaults.
    @Test func applyRejectsModifierlessEnabledBinding() {
        let before = HotKeyController.shared.config
        let result = HotKeyController.shared.apply(
            HotKeyConfig(keyCode: UInt32(kVK_ANSI_A), modifiers: 0, isEnabled: true)
        )
        #expect(result == false)
        #expect(HotKeyController.shared.config == before)
    }
}
