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

    /// Call once at launch to register the persisted binding (if enabled and valid).
    /// `hasRequiredModifier` guards against a tampered/legacy preference that stored
    /// a modifier-less binding, which would otherwise hijack a bare key system-wide.
    func start() {
        if config.isEnabled, config.hasRequiredModifier { hotKey = makeHotKey(for: config) }
    }

    /// Apply a new binding. Returns true on success (registered, or disabled and
    /// saved); false if the binding is invalid (an enabled binding without a
    /// required modifier) or registration failed, in which case the previous
    /// binding is left untouched and nothing is persisted.
    @discardableResult
    func apply(_ new: HotKeyConfig) -> Bool {
        // Reject an enabled binding that lacks ⌘/⌃/⌥: registering a modifier-less
        // hotkey would swallow every press of that key across the system.
        guard !new.isEnabled || new.hasRequiredModifier else { return false }

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

    /// Temporarily unregister the live hotkey (e.g. while the user is recording a
    /// new one) without changing or persisting the config. Pair with `resume()`.
    func suspend() {
        hotKey = nil
    }

    /// Re-register the current binding after a `suspend()`, if enabled. Does not
    /// persist. Returns true when the hotkey is live afterwards (including the
    /// no-op cases: disabled, or already registered); false if re-registration
    /// was attempted and failed (e.g. another process grabbed the combo).
    @discardableResult
    func resume() -> Bool {
        guard config.isEnabled, hotKey == nil else { return true }
        hotKey = makeHotKey(for: config)
        return hotKey != nil
    }

    private func makeHotKey(for config: HotKeyConfig) -> GlobalHotKey? {
        GlobalHotKey(keyCode: config.keyCode, modifiers: config.modifiers) {
            DiffWindowManager.shared.toggle()
        }
    }
}
