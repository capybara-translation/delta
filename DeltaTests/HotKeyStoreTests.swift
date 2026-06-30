import Testing
import Foundation
import Carbon
@testable import Delta

struct HotKeyStoreTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "HotKeyStoreTests"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    @Test func loadReturnsDefaultWhenEmpty() {
        let d = freshDefaults()
        #expect(HotKeyStore.load(from: d) == .default)
    }

    @Test func saveThenLoadRoundTrips() {
        let d = freshDefaults()
        let config = HotKeyConfig(keyCode: UInt32(kVK_ANSI_J),
                                  modifiers: UInt32(cmdKey | shiftKey),
                                  isEnabled: false)
        HotKeyStore.save(config, to: d)
        #expect(HotKeyStore.load(from: d) == config)
    }

    @Test func enabledDefaultsTrueWhenMissing() {
        let d = freshDefaults()
        d.set(Int(kVK_ANSI_K), forKey: "hotKeyKeyCode")
        d.set(Int(cmdKey), forKey: "hotKeyModifiers")
        // no enabled key set
        #expect(HotKeyStore.load(from: d).isEnabled)
    }
}
