import Foundation

/// Persists a HotKeyConfig in UserDefaults. Missing values fall back to the default binding.
enum HotKeyStore {
    private static let keyCodeKey = "hotKeyKeyCode"
    private static let modifiersKey = "hotKeyModifiers"
    private static let enabledKey = "hotKeyEnabled"

    static func load(from defaults: UserDefaults = .standard) -> HotKeyConfig {
        guard defaults.object(forKey: keyCodeKey) != nil,
              defaults.object(forKey: modifiersKey) != nil else {
            return .default
        }
        let keyCode = UInt32(defaults.integer(forKey: keyCodeKey))
        let modifiers = UInt32(defaults.integer(forKey: modifiersKey))
        let enabled = defaults.object(forKey: enabledKey) as? Bool ?? true
        return HotKeyConfig(keyCode: keyCode, modifiers: modifiers, isEnabled: enabled)
    }

    static func save(_ config: HotKeyConfig, to defaults: UserDefaults = .standard) {
        defaults.set(Int(config.keyCode), forKey: keyCodeKey)
        defaults.set(Int(config.modifiers), forKey: modifiersKey)
        defaults.set(config.isEnabled, forKey: enabledKey)
    }
}
