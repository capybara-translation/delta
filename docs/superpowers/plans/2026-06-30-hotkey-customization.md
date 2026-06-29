# Global Hotkey Customization UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users record, change, disable, and reset the global show/hide hotkey (currently the fixed `⌃⌥D`) from the Settings window.

**Architecture:** A pure formatter + a value-type config + a `UserDefaults` store hold and describe the binding. A `@MainActor` controller owns the (re)registration of a Carbon `GlobalHotKey` and rolls back on failure. A SwiftUI Settings section with an `NSView`-backed recorder drives changes through the controller.

**Tech Stack:** Swift, SwiftUI, AppKit, Carbon (`RegisterEventHotKey`), Swift Testing (`import Testing`), XcodeGen.

## Global Constraints

- No external dependencies — system frameworks only (Carbon already in use).
- Deployment target macOS 14; Swift 5.0.
- New `.swift` files under `Delta/` are picked up by XcodeGen; run `xcodegen generate` after adding/removing files before building or testing.
- Build/test require `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (xcode-select points at CLT).
- Default binding stays `⌃⌥D`, enabled.
- A valid binding MUST include at least one of `⌘`/`⌃`/`⌥` (Carbon `cmdKey`/`controlKey`/`optionKey`); `⇧`-only or bare keys are rejected.
- Modifier display order is Apple-conventional: `⌃⌥⇧⌘`.
- The hotkey action is always `DiffWindowManager.shared.toggle()`.

**Build command:**
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Delta.xcodeproj -scheme Delta -destination 'platform=macOS' build
```
**Test command:**
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Delta.xcodeproj -scheme Delta -destination 'platform=macOS' test
```

---

### Task 1: KeyCodeFormatter (pure formatting + flag conversion)

**Files:**
- Create: `Delta/HotKey/KeyCodeFormatter.swift`
- Test: `DeltaTests/KeyCodeFormatterTests.swift`

**Interfaces:**
- Consumes: Carbon constants (`kVK_*`, `cmdKey`, `optionKey`, `controlKey`, `shiftKey`), `NSEvent.ModifierFlags`.
- Produces:
  - `KeyCodeFormatter.modifierSymbols(_ carbonModifiers: UInt32) -> String`
  - `KeyCodeFormatter.keyString(_ keyCode: UInt32) -> String`
  - `KeyCodeFormatter.string(keyCode: UInt32, modifiers: UInt32) -> String`
  - `KeyCodeFormatter.carbonFlags(from flags: NSEvent.ModifierFlags) -> UInt32`
  - `KeyCodeFormatter.modifierFlags(from carbonModifiers: UInt32) -> NSEvent.ModifierFlags`

- [ ] **Step 1: Write the failing test**

```swift
// DeltaTests/KeyCodeFormatterTests.swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run the test command. Expected: FAIL — `KeyCodeFormatter` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
// Delta/HotKey/KeyCodeFormatter.swift
import AppKit
import Carbon

/// Pure helpers to render a key code + Carbon modifier flags as a human-readable
/// shortcut string, and to convert between AppKit and Carbon modifier flags.
enum KeyCodeFormatter {
    /// Apple-conventional order: Control, Option, Shift, Command.
    static func modifierSymbols(_ carbonModifiers: UInt32) -> String {
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if carbonModifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if carbonModifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        return s
    }

    static func string(keyCode: UInt32, modifiers: UInt32) -> String {
        modifierSymbols(modifiers) + keyString(keyCode)
    }

    static func carbonFlags(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var c: UInt32 = 0
        if flags.contains(.command) { c |= UInt32(cmdKey) }
        if flags.contains(.option)  { c |= UInt32(optionKey) }
        if flags.contains(.control) { c |= UInt32(controlKey) }
        if flags.contains(.shift)   { c |= UInt32(shiftKey) }
        return c
    }

    static func modifierFlags(from carbonModifiers: UInt32) -> NSEvent.ModifierFlags {
        var f = NSEvent.ModifierFlags()
        if carbonModifiers & UInt32(cmdKey)     != 0 { f.insert(.command) }
        if carbonModifiers & UInt32(optionKey)  != 0 { f.insert(.option) }
        if carbonModifiers & UInt32(controlKey) != 0 { f.insert(.control) }
        if carbonModifiers & UInt32(shiftKey)   != 0 { f.insert(.shift) }
        return f
    }

    static func keyString(_ keyCode: UInt32) -> String {
        map[keyCode] ?? "Key \(keyCode)"
    }

    private static let map: [UInt32: String] = [
        // Letters
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        // Digits
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
        // Punctuation
        UInt32(kVK_ANSI_Minus): "-", UInt32(kVK_ANSI_Equal): "=",
        UInt32(kVK_ANSI_LeftBracket): "[", UInt32(kVK_ANSI_RightBracket): "]",
        UInt32(kVK_ANSI_Backslash): "\\", UInt32(kVK_ANSI_Semicolon): ";",
        UInt32(kVK_ANSI_Quote): "'", UInt32(kVK_ANSI_Comma): ",",
        UInt32(kVK_ANSI_Period): ".", UInt32(kVK_ANSI_Slash): "/",
        UInt32(kVK_ANSI_Grave): "`",
        // Named keys
        UInt32(kVK_Space): "Space", UInt32(kVK_Return): "↩", UInt32(kVK_Tab): "⇥",
        UInt32(kVK_Escape): "⎋", UInt32(kVK_Delete): "⌫", UInt32(kVK_ForwardDelete): "⌦",
        UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_Home): "↖", UInt32(kVK_End): "↘",
        UInt32(kVK_PageUp): "⇞", UInt32(kVK_PageDown): "⇟",
        // Function keys
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
    ]
}
```

- [ ] **Step 4: Regenerate project and run tests**

```bash
xcodegen generate
```
Then run the test command. Expected: PASS (all `KeyCodeFormatterTests`).

- [ ] **Step 5: Commit**

```bash
git add Delta/HotKey/KeyCodeFormatter.swift DeltaTests/KeyCodeFormatterTests.swift
git commit -m "feat: KeyCodeFormatter（ホットキー表示と修飾フラグ変換）"
```

---

### Task 2: HotKeyConfig (value type)

**Files:**
- Create: `Delta/HotKey/HotKeyConfig.swift`
- Test: `DeltaTests/HotKeyConfigTests.swift`

**Interfaces:**
- Consumes: `KeyCodeFormatter.string(keyCode:modifiers:)`, Carbon constants.
- Produces:
  - `struct HotKeyConfig: Equatable { var keyCode: UInt32; var modifiers: UInt32; var isEnabled: Bool }`
  - `HotKeyConfig.default` (`⌃⌥D`, enabled)
  - `HotKeyConfig.hasRequiredModifier -> Bool`
  - `HotKeyConfig.displayString -> String`

- [ ] **Step 1: Write the failing test**

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run the test command. Expected: FAIL — `HotKeyConfig` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
// Delta/HotKey/HotKeyConfig.swift
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
```

- [ ] **Step 4: Run tests**

Run the test command. Expected: PASS (`HotKeyConfigTests`).

- [ ] **Step 5: Commit**

```bash
git add Delta/HotKey/HotKeyConfig.swift DeltaTests/HotKeyConfigTests.swift
git commit -m "feat: HotKeyConfig（ホットキー設定の値型）"
```

---

### Task 3: HotKeyStore (UserDefaults persistence)

**Files:**
- Create: `Delta/HotKey/HotKeyStore.swift`
- Test: `DeltaTests/HotKeyStoreTests.swift`

**Interfaces:**
- Consumes: `HotKeyConfig`.
- Produces:
  - `HotKeyStore.load(from: UserDefaults = .standard) -> HotKeyConfig`
  - `HotKeyStore.save(_ config: HotKeyConfig, to: UserDefaults = .standard)`

- [ ] **Step 1: Write the failing test**

```swift
// DeltaTests/HotKeyStoreTests.swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run the test command. Expected: FAIL — `HotKeyStore` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
// Delta/HotKey/HotKeyStore.swift
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
```

- [ ] **Step 4: Run tests**

Run the test command. Expected: PASS (`HotKeyStoreTests`).

- [ ] **Step 5: Commit**

```bash
git add Delta/HotKey/HotKeyStore.swift DeltaTests/HotKeyStoreTests.swift
git commit -m "feat: HotKeyStore（ホットキー設定の永続化）"
```

---

### Task 4: GlobalHotKey — failable init to surface registration failure

**Files:**
- Modify: `Delta/HotKey/GlobalHotKey.swift`

**Interfaces:**
- Produces: `GlobalHotKey.init?(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void)` — returns `nil` if `InstallEventHandler` or `RegisterEventHotKey` fails. `deinit` unchanged.
- Consumed by: Task 5 (`HotKeyController`).

This task has no unit test: `RegisterEventHotKey` registers a real system hotkey, so success/failure is environment-dependent. Verify by build + the end-to-end manual check in Task 8.

- [ ] **Step 1: Replace the initializer with a failable one**

Replace the whole `init(...)` body (currently `Delta/HotKey/GlobalHotKey.swift:12-44`) with:

```swift
    init?(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        self.handler = handler

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                hotKey.handler()
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )
        guard installStatus == noErr else { return nil }

        // Signature 'DELT' (0x44454C54) keeps this hotkey id distinct.
        let hotKeyID = EventHotKeyID(signature: OSType(0x44454C54), id: 1)
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
            return nil
        }
    }
```

(The stored properties and `deinit` at the top/bottom of the file stay as they are.)

- [ ] **Step 2: Regenerate and build**

```bash
xcodegen generate
```
Then run the build command. Expected: compiles with no call-site change. The
existing call site in `Delta/DeltaApp.swift` is `hotKey = GlobalHotKey(...) { ... }`
where `hotKey` is already typed `GlobalHotKey?`. The failable initializer now
returns `GlobalHotKey?`, so the existing assignment still type-checks unchanged.
(That call site is removed entirely in Task 8.)

- [ ] **Step 3: Run tests**

Run the test command. Expected: PASS (existing suite unaffected; 56 prior tests plus Tasks 1–3 still green).

- [ ] **Step 4: Commit**

```bash
git add Delta/HotKey/GlobalHotKey.swift
git commit -m "refactor: GlobalHotKey を失敗可能イニシャライザ化（登録失敗を表面化）"
```

---

### Task 5: HotKeyController (registration + rollback)

**Files:**
- Create: `Delta/HotKey/HotKeyController.swift`

**Interfaces:**
- Consumes: `HotKeyConfig`, `HotKeyStore`, `GlobalHotKey.init?`, `DiffWindowManager.shared.toggle()`.
- Produces:
  - `HotKeyController.shared` (`@MainActor`)
  - `HotKeyController.config: HotKeyConfig` (read-only)
  - `HotKeyController.start()`
  - `HotKeyController.apply(_ new: HotKeyConfig) -> Bool` (`@discardableResult`)

No unit test: `apply` registers a real hotkey via Carbon. Verified by Task 8 manual check. Logic is kept tiny and delegates to the already-tested `HotKeyStore`/`GlobalHotKey`.

- [ ] **Step 1: Write the implementation**

```swift
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
```

- [ ] **Step 2: Regenerate and build**

```bash
xcodegen generate
```
Then run the build command. Expected: compiles.

- [ ] **Step 3: Run tests**

Run the test command. Expected: PASS (no regressions).

- [ ] **Step 4: Commit**

```bash
git add Delta/HotKey/HotKeyController.swift
git commit -m "feat: HotKeyController（再登録とロールバック）"
```

---

### Task 6: ShortcutRecorder (NSView-backed key recorder)

**Files:**
- Create: `Delta/Views/ShortcutRecorder.swift`

**Interfaces:**
- Consumes: `KeyCodeFormatter.carbonFlags(from:)`, Carbon constants.
- Produces:
  - `final class RecorderButton: NSButton` with `var onCapture: ((UInt32, UInt32) -> Void)?` and `var shortcutTitle: String`.
  - `struct ShortcutRecorder: NSViewRepresentable` with `let displayString: String`, `let isEnabled: Bool`, `let onCapture: (UInt32, UInt32) -> Void`.

No unit test: `keyDown` / first-responder behavior is UI/runtime. Verified by Task 8 manual check.

- [ ] **Step 1: Write the implementation**

```swift
// Delta/Views/ShortcutRecorder.swift
import SwiftUI
import Carbon

/// A push-button that records a key combination: click to start, then press the
/// desired keys. Escape cancels. A combination without Command/Control/Option is
/// rejected with a beep (recording continues).
final class RecorderButton: NSButton {
    var onCapture: ((UInt32, UInt32) -> Void)?
    var shortcutTitle: String = "" {
        didSet { if !recording { title = shortcutTitle } }
    }

    private var recording = false {
        didSet { title = recording ? "Type shortcut…" : shortcutTitle }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setButtonType(.momentaryPushIn)
        bezelStyle = .rounded
        target = self
        action = #selector(startRecording)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { isEnabled }

    @objc private func startRecording() {
        guard isEnabled else { return }
        recording = true
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }

        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }

        let carbon = KeyCodeFormatter.carbonFlags(
            from: event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        )
        guard carbon & UInt32(cmdKey | controlKey | optionKey) != 0 else {
            NSSound.beep()   // require a real modifier; keep recording
            return
        }

        onCapture?(UInt32(event.keyCode), carbon)
        stopRecording()
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        return super.resignFirstResponder()
    }

    private func stopRecording() {
        recording = false
        window?.makeFirstResponder(nil)
    }
}

/// SwiftUI wrapper around RecorderButton.
struct ShortcutRecorder: NSViewRepresentable {
    let displayString: String
    let isEnabled: Bool
    let onCapture: (UInt32, UInt32) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.shortcutTitle = displayString
        button.isEnabled = isEnabled
        button.onCapture = onCapture
        return button
    }

    func updateNSView(_ nsView: RecorderButton, context: Context) {
        nsView.shortcutTitle = displayString
        nsView.isEnabled = isEnabled
        nsView.onCapture = onCapture
    }
}
```

- [ ] **Step 2: Regenerate and build**

```bash
xcodegen generate
```
Then run the build command. Expected: compiles.

- [ ] **Step 3: Commit**

```bash
git add Delta/Views/ShortcutRecorder.swift
git commit -m "feat: ShortcutRecorder（ホットキー録音フィールド）"
```

---

### Task 7: SettingsView — hotkey section

**Files:**
- Modify: `Delta/Views/SettingsView.swift`

**Interfaces:**
- Consumes: `HotKeyController.shared`, `HotKeyConfig`, `ShortcutRecorder`.

No unit test: SwiftUI view wiring. Verified by Task 8 manual check.

- [ ] **Step 1: Replace SettingsView with the hotkey-aware version**

Replace the whole contents of `Delta/Views/SettingsView.swift` with:

```swift
import SwiftUI

struct SettingsView: View {
    @AppStorage("keepTextOnReopen") private var keepText = true
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var hotKey = HotKeyController.shared.config
    @State private var hotKeyError: String?

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        Form {
            Toggle("Keep text between launches", isOn: $keepText)

            Toggle("Launch at login", isOn: Binding(
                get: { launchAtLogin },
                set: { newValue in
                    try? LaunchAtLogin.setEnabled(newValue)
                    launchAtLogin = LaunchAtLogin.isEnabled
                }
            ))

            Toggle("Enable global hotkey", isOn: Binding(
                get: { hotKey.isEnabled },
                set: { enabled in
                    applyHotKey(HotKeyConfig(keyCode: hotKey.keyCode,
                                             modifiers: hotKey.modifiers,
                                             isEnabled: enabled))
                }
            ))

            LabeledContent("Shortcut") {
                ShortcutRecorder(
                    displayString: hotKey.displayString,
                    isEnabled: hotKey.isEnabled,
                    onCapture: { keyCode, modifiers in
                        applyHotKey(HotKeyConfig(keyCode: keyCode,
                                                 modifiers: modifiers,
                                                 isEnabled: true))
                    }
                )
                .frame(width: 140)
                .disabled(!hotKey.isEnabled)
            }

            if let hotKeyError {
                Text(hotKeyError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button("Reset to Default") { applyHotKey(.default) }

            LabeledContent("Version", value: appVersion)
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            launchAtLogin = LaunchAtLogin.isEnabled
            hotKey = HotKeyController.shared.config
        }
    }

    private func applyHotKey(_ config: HotKeyConfig) {
        if HotKeyController.shared.apply(config) {
            hotKeyError = nil
        } else {
            hotKeyError = "This shortcut is already in use."
        }
        // Reflect the controller's actual state (rolled back on failure).
        hotKey = HotKeyController.shared.config
    }
}
```

- [ ] **Step 2: Regenerate and build**

```bash
xcodegen generate
```
Then run the build command. Expected: compiles.

- [ ] **Step 3: Commit**

```bash
git add Delta/Views/SettingsView.swift
git commit -m "feat: Settings にホットキー（有効化・録音・リセット）UI を追加"
```

---

### Task 8: Wire AppDelegate to HotKeyController + end-to-end verification

**Files:**
- Modify: `Delta/DeltaApp.swift`

**Interfaces:**
- Consumes: `HotKeyController.shared.start()`.

- [ ] **Step 1: Replace the fixed registration with the controller**

In `Delta/DeltaApp.swift`, remove the stored `hotKey` property and the inline `GlobalHotKey` registration. The `AppDelegate` becomes:

```swift
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        clearTextIfNeeded()
        HotKeyController.shared.start()
    }

    /// When "keep text between launches" is off, start each launch with empty input.
    /// A missing key (first launch) is treated as true (keep).
    private func clearTextIfNeeded() {
        let defaults = UserDefaults.standard
        let keep = defaults.object(forKey: "keepTextOnReopen") as? Bool ?? true
        if !keep {
            defaults.removeObject(forKey: "textA")
            defaults.removeObject(forKey: "textB")
        }
    }
}
```

Also remove the now-unused `import Carbon` from `DeltaApp.swift` if nothing else in that file uses Carbon (the `kVK_ANSI_D`/`controlKey`/`optionKey` references are gone). Keep `import SwiftUI`.

- [ ] **Step 2: Regenerate, build, and run the full test suite**

```bash
xcodegen generate
```
Then run the build command (expected: compiles) and the test command (expected: PASS — Tasks 1–3 suites plus all prior tests green).

- [ ] **Step 3: Manual end-to-end verification**

Build and launch:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Delta.xcodeproj -scheme Delta -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/Delta.app
```
Verify each:
1. Default `⌃⌥D` toggles the diff window.
2. Open Settings → it shows "Enable global hotkey" on, "Shortcut" = `⌃⌥D`.
3. Click the Shortcut field, press a new combo (e.g. `⌘⌥G`) → field shows `⌘⌥G`; the new combo now toggles the window and `⌃⌥D` no longer does.
4. Try a bare key (no modifier) or Shift-only → rejected (beep), field unchanged.
5. Toggle "Enable global hotkey" off → the combo no longer toggles; on → it works again.
6. "Reset to Default" → field returns to `⌃⌥D`, which toggles again.
7. Quit and relaunch → the last chosen binding and enabled state persist.

- [ ] **Step 4: Commit**

```bash
git add Delta/DeltaApp.swift
git commit -m "feat: 起動時のホットキー登録を HotKeyController に委譲"
```

---

## Notes for the implementer

- Keep all new hotkey files under `Delta/HotKey/` (formatter, config, store, controller, and the existing `GlobalHotKey.swift`); the recorder view lives under `Delta/Views/`.
- After this plan, consider a follow-up release (version bump + tag) only when the user asks.
