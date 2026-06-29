# Delta Diff Cmd+Tab 動的ポリシー Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Diff ウィンドウ表示中だけ `.regular`（Dock＋Cmd+Tab に出る）、非表示時は `.accessory` に動的切替する。

**Architecture:** `DiffWindowManager` を `NSObject, NSWindowDelegate` 化し、show で `.regular`、hide/close で `.accessory` に切替える。`LSUIElement: true` は維持（起動時 accessory）。

**Tech Stack:** Swift（言語モード5）/ AppKit / SwiftUI / XcodeGen。

## Global Constraints

- デプロイメントターゲット macOS 14.0 維持 / SWIFT_VERSION 5.0 / 外部 SPM 依存なし / `LSUIElement: true` 維持
- `DiffEngine`・各 View・`HistoryStore`・`HTMLExporter`・`GlobalHotKey`・`LaunchAtLogin`・`DeltaApp` は無変更
- ビルド・テストは `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` を前置
- ファイル追加・削除はないので `xcodegen generate` は不要
- ビルド/テストの stderr の `IDESimulatorFoundation`/`[Connection]` 警告は無害。合否は `** BUILD SUCCEEDED **` / `** TEST SUCCEEDED **` 行で判断
- 表示中は `.regular`、非表示/閉じるは `.accessory`。`orderOut` は `windowWillClose` を発火しないため hide 経路でも明示的に `.accessory` にする
- このタスクは AppKit 統合のため新規の自動テストは追加しない。検証はビルド＋手動確認。既存56テストは緑のまま

ビルドコマンド（参照）:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -configuration Debug -derivedDataPath build build
```
テストコマンド（参照）:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -destination 'platform=macOS' test
```

---

### Task 1: DiffWindowManager の動的アクティベーションポリシー

ウィンドウ表示で `.regular`、非表示/閉じるで `.accessory` に切替える。AppKit 統合のためビルド＋手動確認で検証する。

**Files:**
- Modify: `Delta/Window/DiffWindowManager.swift`（全置換）

**Interfaces:**
- Consumes: `DiffWindowView`（既存）
- Produces: `DiffWindowManager`（公開メソッド `show()` / `toggle()` は不変。内部で `hide()` を追加、`NSWindowDelegate` 準拠）

- [ ] **Step 1: DiffWindowManager を全置換**

Replace the entire contents of `Delta/Window/DiffWindowManager.swift`:
```swift
import AppKit
import SwiftUI

/// Holds and presents a single diff window instance, and switches the app's
/// activation policy so it appears in Cmd+Tab and the Dock only while the
/// window is visible (otherwise it stays a menu-bar accessory).
@MainActor
final class DiffWindowManager: NSObject, NSWindowDelegate {
    static let shared = DiffWindowManager()
    private var window: NSWindow?

    private override init() {
        super.init()
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: DiffWindowView())
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "Delta Diff"
            newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            newWindow.setContentSize(NSSize(width: 540, height: 480))
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            newWindow.delegate = self
            window = newWindow
        }
        // Become a regular app while the window is visible so it shows in Cmd+Tab and the Dock.
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        // Force activation so the window comes to the front from BOTH the global
        // hotkey (background) and the menu-bar item.
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    /// Toggles the window: hides it when it is the frontmost key window,
    /// otherwise shows and activates it (creating it on first use via show()).
    func toggle() {
        if let window, window.isVisible, window.isKeyWindow {
            hide()
        } else {
            show()
        }
    }

    /// Hides the window via orderOut and returns to a menu-bar accessory.
    /// (orderOut does not fire windowWillClose, so the policy is reset here.)
    private func hide() {
        window?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    // Closing the window (red button / ⌘W) returns to a menu-bar accessory.
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
```

- [ ] **Step 2: ビルド**

Run:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -configuration Debug -derivedDataPath build build 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: テストが引き続き通ることを確認**

Run:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -destination 'platform=macOS' test 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`（既存56 全通過。新規テストなし）

- [ ] **Step 4: 起動して手動確認**

新バイナリで確認するため旧プロセスを止めてから開く:
```bash
pkill -x Delta; sleep 1
open build/Build/Products/Debug/Delta.app && sleep 2 && pgrep -x Delta
```
プロセスが生きていること（即クラッシュしないこと）を確認。実装者はここまで（プロセス生存）を報告する。以降はコントローラ/ユーザーが確認する:
1. メニューバー δ →「Open Delta Diff」（または ⌃⌥D）でウィンドウを開く → **Cmd+Tab と Dock に Delta Diff が出る**
2. 赤ボタン/⌘W で閉じる → Cmd+Tab/Dock から消える
3. ⌃⌥D で隠す → 消える、再度 ⌃⌥D で出す → 現れる
4. メニューバー δ・diff 実行・Settings・履歴・前面化が引き続き動く

- [ ] **Step 5: コミット**

```bash
git add Delta/Window/DiffWindowManager.swift
git commit -m "feat: ウィンドウ表示中だけ Cmd+Tab/Dock に出す（動的アクティベーションポリシー）"
```

---

## 完了の定義

- `xcodebuild build` 成功、既存56テストが緑
- 手動確認（Task 1 Step 4）で 表示中のみ Cmd+Tab/Dock に出て、閉じる/隠すと消える
- デプロイメントターゲット macOS 14・`LSUIElement: true`・既存機能・diff ロジックは無変更
