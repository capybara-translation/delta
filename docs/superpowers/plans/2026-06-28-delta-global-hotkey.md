# Delta グローバルホットキー Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** アプリ起動時にグローバルホットキー ⌃⌥D を登録し、押下で Diff ウィンドウをトグル（前面表示↔隠す）する。

**Architecture:** Carbon `RegisterEventHotKey` を薄くラップした `GlobalHotKey` を `AppDelegate` が保持し、発火で `DiffWindowManager.toggle()` を呼ぶ。外部依存は追加しない（Carbon はシステムフレームワーク）。

**Tech Stack:** Swift（言語モード5）/ SwiftUI / AppKit / Carbon / XcodeGen。

## Global Constraints

- デプロイメントターゲット macOS 14.0 維持 / SWIFT_VERSION 5.0 / 外部 SPM 依存なし（Carbon はシステムフレームワーク）
- `DiffEngine`・`CodePointFormatter`・`TabKeyResolver`・各 View・`CodePointTextView` は無変更
- ビルド・テストは `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` を前置
- **Swift ファイルを追加したら必ず `xcodegen generate`**（.xcodeproj は project.yml から生成、gitignore 済み）
- ビルド/テストの stderr の `IDESimulatorFoundation`/`[Connection]` 警告は無害。合否は `** BUILD SUCCEEDED **` / `** TEST SUCCEEDED **` 行で判断
- デフォルト組み合わせ ⌃⌥D（`controlKey | optionKey` + `kVK_ANSI_D`）。アクセシビリティ権限は要求しない
- このタスクはシステム統合のため新規の自動テストを追加しない。検証はビルド＋手動確認。既存39テストは緑のまま

ビルドコマンド（参照）:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -configuration Debug -derivedDataPath build build
```
テストコマンド（参照）:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -destination 'platform=macOS' test
```

---

### Task 1: GlobalHotKey ＋ toggle ＋ AppDelegate 配線

Carbon ホットキー登録、ウィンドウのトグル、起動時登録を一括で配線する。Carbon のシステム統合のため自動テストはなく、ビルド＋手動確認で検証する。

**Files:**
- Create: `Delta/HotKey/GlobalHotKey.swift`
- Modify: `Delta/Window/DiffWindowManager.swift`（`toggle()` を追加）
- Modify: `Delta/DeltaApp.swift`（`AppDelegate` を追加）

**Interfaces:**
- Consumes: `DiffWindowManager.shared.show()`（既存）
- Produces:
  - `final class GlobalHotKey { init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) }`
  - `DiffWindowManager.toggle()`

- [ ] **Step 1: GlobalHotKey を作成**

Create `Delta/HotKey/GlobalHotKey.swift`:
```swift
import AppKit
import Carbon

/// Thin wrapper around Carbon's RegisterEventHotKey for a system-wide hotkey.
/// Fires `handler` on the main thread when the registered combination is pressed.
/// The caller must retain this instance; releasing it unregisters the hotkey.
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let handler: () -> Void

    init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        self.handler = handler

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        _ = InstallEventHandler(
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

        // Signature 'DELT' (0x44454C54) keeps this hotkey id distinct.
        let hotKeyID = EventHotKeyID(signature: OSType(0x44454C54), id: 1)
        _ = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }
}
```

- [ ] **Step 2: DiffWindowManager に toggle() を追加**

In `Delta/Window/DiffWindowManager.swift`, add the `toggle()` method right after the existing `show()` method (before the closing brace of the class):
```swift

    /// Toggles the window: hides it when it is the frontmost key window,
    /// otherwise shows and activates it (creating it on first use via show()).
    func toggle() {
        if let window, window.isVisible, window.isKeyWindow {
            window.orderOut(nil)
        } else {
            show()
        }
    }
```

- [ ] **Step 3: DeltaApp に AppDelegate を追加してホットキーを登録**

Replace the entire contents of `Delta/DeltaApp.swift`:
```swift
import SwiftUI
import Carbon

@main
struct DeltaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Delta", systemImage: "doc.on.doc") {
            Button("Open Diff Window") { DiffWindowManager.shared.show() }
            Divider()
            Button("Quit Delta") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Registers the global hotkey (⌃⌥D) at launch and retains it for the app's lifetime.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        hotKey = GlobalHotKey(
            keyCode: UInt32(kVK_ANSI_D),
            modifiers: UInt32(controlKey | optionKey)
        ) {
            DiffWindowManager.shared.toggle()
        }
    }
}
```

- [ ] **Step 4: プロジェクト再生成してビルド**

新規ファイル追加のため `xcodegen generate` が必須。

Run:
```bash
xcodegen generate && \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -configuration Debug -derivedDataPath build build 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: テストが引き続き通ることを確認**

Run:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -destination 'platform=macOS' test 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`（既存39 全通過。新規テストなし）

- [ ] **Step 6: 起動して手動確認**

新バイナリで確認するため旧プロセスを止めてから開く:
```bash
pkill -x Delta; sleep 1
open build/Build/Products/Debug/Delta.app && sleep 2 && pgrep -x Delta
```
プロセスが生きていること（即クラッシュしないこと）を確認。実装者はここまで（プロセス生存）を報告する。以降のホットキー目視はコントローラ/ユーザーが行う:
1. 別アプリ（例: Finder）を最前面にして ⌃⌥D → Delta ウィンドウが前面に出る
2. 最前面の状態で再度 ⌃⌥D → 隠れる
3. メニューの「Open Diff Window」、diff 実行（⌘↵）、Tab 移動、コードポイント表示が引き続き動く

- [ ] **Step 7: コミット**

```bash
git add Delta/HotKey/GlobalHotKey.swift Delta/Window/DiffWindowManager.swift Delta/DeltaApp.swift
git commit -m "feat: グローバルホットキー ⌃⌥D で Diff ウィンドウをトグル"
```

---

## 完了の定義

- `xcodebuild build` 成功、既存39テストが緑
- 手動確認（Task 1 Step 6）で ⌃⌥D によるウィンドウのトグル（表示↔隠す）が動く
- デプロイメントターゲット macOS 14・既存機能・diff ロジックは無変更
- アクセシビリティ権限を要求しない
