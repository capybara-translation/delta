// Delta/HotKey/HotKeyController.swift
import AppKit

/// Owns the live global hotkey registration. Re-registers on change and rolls
/// back to the previous binding if registration fails (e.g. the combo is taken).
@MainActor
final class HotKeyController {
    static let shared = HotKeyController()

    private(set) var config: HotKeyConfig
    private var hotKey: GlobalHotKey?

    private init() {
        config = HotKeyStore.load()
    }

    /// Call once at launch to register the persisted binding (if enabled).
    func start() {
        if config.isEnabled { hotKey = makeHotKey(for: config) }
    }

    /// Apply a new binding. Returns true on success (registered, or disabled and
    /// saved); false if registration failed, in which case the previous binding
    /// is restored and nothing is persisted.
    @discardableResult
    func apply(_ new: HotKeyConfig) -> Bool {
        let previous = config

        // Tear down the current registration first so the hotkey id / combo is free.
        hotKey = nil
        config = new

        if new.isEnabled {
            guard let registered = makeHotKey(for: new) else {
                // Roll back: restore and re-register the previous binding.
                config = previous
                if previous.isEnabled { hotKey = makeHotKey(for: previous) }
                return false
            }
            hotKey = registered
        }

        HotKeyStore.save(config)
        return true
    }

    private func makeHotKey(for config: HotKeyConfig) -> GlobalHotKey? {
        GlobalHotKey(keyCode: config.keyCode, modifiers: config.modifiers) {
            DiffWindowManager.shared.toggle()
        }
    }
}
