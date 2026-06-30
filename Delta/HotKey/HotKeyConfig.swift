import Carbon

/// A global hotkey binding: a key code, Carbon modifier flags, and whether it is enabled.
struct HotKeyConfig: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32   // Carbon: cmdKey | optionKey | controlKey | shiftKey
    var isEnabled: Bool

    static let `default` = HotKeyConfig(
        keyCode: UInt32(kVK_ANSI_D),
        modifiers: UInt32(controlKey | optionKey),
        isEnabled: true
    )

    /// True when at least one of Command/Control/Option is present.
    /// Shift-only or modifier-less bindings are rejected (they would hijack typing).
    var hasRequiredModifier: Bool {
        modifiers & UInt32(cmdKey | controlKey | optionKey) != 0
    }

    var displayString: String {
        KeyCodeFormatter.string(keyCode: keyCode, modifiers: modifiers)
    }
}
