# Delta 設定の永続化（テキスト保持） Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 設定トグル「Keep text between launches」（既定 ON）で入力テキストを再起動後も復元/毎回空から開始を切り替え、標準の設定ウィンドウ（⌘,）で操作できるようにする。

**Architecture:** `textA`/`textB` を `@AppStorage` で永続化。設定は `@AppStorage("keepTextOnReopen")`。OFF のときは `AppDelegate` の起動フックで保存テキストを削除して毎回空から開始。設定 UI は SwiftUI の `Settings` シーン＋`SettingsLink`。

**Tech Stack:** Swift（言語モード5）/ SwiftUI / AppKit / XcodeGen。

## Global Constraints

- デプロイメントターゲット macOS 14.0 維持 / SWIFT_VERSION 5.0 / 外部 SPM 依存なし
- `DiffEngine`・`SplitDiffView`・`DiffCellView`・`CodePointTextView`・`DiffEditorView`・`DiffWindowManager`・`GlobalHotKey`・`TabKeyResolver`・`CodePointFormatter` は無変更
- ビルド・テストは `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` を前置
- **Swift ファイルを追加したら必ず `xcodegen generate`**（.xcodeproj は project.yml から生成、gitignore 済み）
- ビルド/テストの stderr の `IDESimulatorFoundation`/`[Connection]` 警告は無害。合否は `** BUILD SUCCEEDED **` / `** TEST SUCCEEDED **` 行で判断
- `keepTextOnReopen` の既定は `true`（キー未設定の初回起動も保持扱い）
- セマンティクス: ON=再起動後も `textA`/`textB` を復元 / OFF=起動時にクリアして毎回空（セッション中は保持）
- このタスクは設定配線が中心で新規の自動テストは追加しない。検証はビルド＋手動確認。既存39テストは緑のまま

ビルドコマンド（参照）:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -configuration Debug -derivedDataPath build build
```
テストコマンド（参照）:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -destination 'platform=macOS' test
```

---

### Task 1: テキスト保持設定と設定ウィンドウ

`textA`/`textB` を永続化し、設定トグルと標準設定ウィンドウを追加する。設定配線が中心のためビルド＋手動確認で検証する。

**Files:**
- Create: `Delta/Views/SettingsView.swift`
- Modify: `Delta/Views/DiffWindowView.swift`（`textA`/`textB` を `@AppStorage` に）
- Modify: `Delta/DeltaApp.swift`（Settings シーン＋`SettingsLink`＋起動時クリア）

**Interfaces:**
- Consumes: なし（既存 `DiffWindowManager.shared` 等）
- Produces:
  - `struct SettingsView: View`（`@AppStorage("keepTextOnReopen")` を操作）
  - 永続化キー `"textA"`, `"textB"`, `"keepTextOnReopen"`

- [ ] **Step 1: SettingsView を作成**

Create `Delta/Views/SettingsView.swift`:
```swift
import SwiftUI

struct SettingsView: View {
    @AppStorage("keepTextOnReopen") private var keepText = true

    var body: some View {
        Form {
            Toggle("Keep text between launches", isOn: $keepText)
        }
        .padding(20)
        .frame(width: 360)
    }
}
```

- [ ] **Step 2: DiffWindowView の textA/textB を @AppStorage にする**

In `Delta/Views/DiffWindowView.swift`, replace the two `@State` text properties:
```swift
    @State private var textA = ""
    @State private var textB = ""
```
with:
```swift
    @AppStorage("textA") private var textA = ""
    @AppStorage("textB") private var textB = ""
```
Leave everything else (`orientation`, `rows`, `body`, `run()`, the `DiffEditorView`/`SplitDiffView` usage) unchanged. `$textA`/`$textB` continue to work as bindings.

- [ ] **Step 3: DeltaApp に設定シーン・メニュー項目・起動時クリアを追加**

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
            SettingsLink { Text("Settings…") }
            Divider()
            Button("Quit Delta") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }
}

/// Registers the global hotkey (⌃⌥D) at launch, retains it for the app's lifetime,
/// and clears persisted text at launch when text retention is off.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        clearTextIfNeeded()
        hotKey = GlobalHotKey(
            keyCode: UInt32(kVK_ANSI_D),
            modifiers: UInt32(controlKey | optionKey)
        ) {
            DiffWindowManager.shared.toggle()
        }
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
プロセスが生きていること（即クラッシュしないこと）を確認。実装者はここまで（プロセス生存）を報告する。以降の保持挙動はコントローラ/ユーザーが確認する:
1. 設定 ON（既定）でウィンドウを開き A/B にテキスト入力 → Delta を終了し再起動 → テキストが復元される
2. メニュー「Settings…」(または ⌘,) で設定ウィンドウを開き Toggle を OFF → Delta を終了し再起動 → 空で始まる
3. 既存の diff 実行（⌘↵）、side-by-side、コードポイント表示、Tab 移動、⌃⌥D が引き続き動く

- [ ] **Step 7: コミット**

```bash
git add Delta/Views/SettingsView.swift Delta/Views/DiffWindowView.swift Delta/DeltaApp.swift
git commit -m "feat: テキスト保持設定と標準設定ウィンドウを追加"
```

---

## 完了の定義

- `xcodebuild build` 成功、既存39テストが緑
- 手動確認（Task 1 Step 6）で ON=再起動後に復元 / OFF=空で開始 / 設定ウィンドウが開き Toggle が効く
- デプロイメントターゲット macOS 14・既存機能・diff ロジックは無変更
