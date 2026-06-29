# Delta Diff Launch at login Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 設定ウィンドウに「Launch at login」トグルを追加し、`SMAppService` でログイン時自動起動を切り替える。

**Architecture:** `SMAppService.mainApp` の薄いラッパ `LaunchAtLogin` を追加し、`SettingsView` のトグルから register/unregister。状態は OS の `status` を真実の源にする。

**Tech Stack:** Swift（言語モード5）/ SwiftUI / ServiceManagement / XcodeGen。

## Global Constraints

- デプロイメントターゲット macOS 14.0 維持 / SWIFT_VERSION 5.0 / 外部 SPM 依存なし（ServiceManagement はシステムフレームワーク）
- `DiffEngine`・`SplitDiffView`・`DiffCellView`・`CodePointTextView`・`DiffEditorView`・`DiffWindowView`・`HistoryStore`・`HistoryView`・`HTMLExporter`・`DiffWindowManager`・`GlobalHotKey` は無変更
- ビルド・テストは `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` を前置
- **Swift ファイルを追加したら必ず `xcodegen generate`**（.xcodeproj は project.yml から生成、gitignore 済み）
- ビルド/テストの stderr の `IDESimulatorFoundation`/`[Connection]` 警告は無害。合否は `** BUILD SUCCEEDED **` / `** TEST SUCCEEDED **` 行で判断
- 状態は `SMAppService.mainApp.status` を真実の源にし、`@AppStorage` で二重管理しない。失敗時はトグルを実状態へ戻す（アラートなし）。起動時の自動 register はしない
- このタスクはシステム統合のため新規の自動テストは追加しない。検証はビルド＋手動確認。既存56テストは緑のまま

ビルドコマンド（参照）:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -configuration Debug -derivedDataPath build build
```
テストコマンド（参照）:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -destination 'platform=macOS' test
```

---

### Task 1: LaunchAtLogin ラッパと設定トグル

`SMAppService` ラッパを追加し、設定ウィンドウにトグルを配線する。システム統合のためビルド＋手動確認で検証する。

**Files:**
- Create: `Delta/Models/LaunchAtLogin.swift`
- Modify: `Delta/Views/SettingsView.swift`（全置換）

**Interfaces:**
- Consumes: なし（`SMAppService`）
- Produces:
  - `enum LaunchAtLogin { static var isEnabled: Bool; static func setEnabled(_ enabled: Bool) throws }`

- [ ] **Step 1: LaunchAtLogin を作成**

Create `Delta/Models/LaunchAtLogin.swift`:
```swift
import ServiceManagement

/// Thin wrapper over SMAppService.mainApp for "launch at login".
/// The OS registration status is the source of truth; this app does not persist it separately.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
```

- [ ] **Step 2: SettingsView にトグルを追加**

Replace the entire contents of `Delta/Views/SettingsView.swift`:
```swift
import SwiftUI

struct SettingsView: View {
    @AppStorage("keepTextOnReopen") private var keepText = true
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

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
                    // Reflect the real OS status (reverts the toggle if it failed).
                    launchAtLogin = LaunchAtLogin.isEnabled
                }
            ))

            LabeledContent("Version", value: appVersion)
        }
        .padding(20)
        .frame(width: 360)
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }
}
```

- [ ] **Step 3: プロジェクト再生成してビルド**

新規ファイル追加のため `xcodegen generate` が必須。

Run:
```bash
xcodegen generate && \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -configuration Debug -derivedDataPath build build 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: テストが引き続き通ることを確認**

Run:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -destination 'platform=macOS' test 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`（既存56 全通過。新規テストなし）

- [ ] **Step 5: 起動して手動確認**

新バイナリで確認するため旧プロセスを止めてから開く:
```bash
pkill -x Delta; sleep 1
open build/Build/Products/Debug/Delta.app && sleep 2 && pgrep -x Delta
```
プロセスが生きていること（即クラッシュしないこと）を確認。実装者はここまで（プロセス生存）を報告する。以降はコントローラ/ユーザーが確認する:
1. 設定ウィンドウ（⌘,）→「Launch at login」を ON → システム設定 > 一般 > ログイン項目に Delta Diff が出る
2. OFF → ログイン項目から消える
3. （任意）ログアウト/再ログインまたは再起動で自動起動を確認
4. 既存の diff・履歴・設定・HTML エクスポート・Tab・⌃⌥D が引き続き動く
※開発版（build/ パス）での登録は不安定なので、実用確認は `/Applications` 版が望ましい。

- [ ] **Step 6: コミット**

```bash
git add Delta/Models/LaunchAtLogin.swift Delta/Views/SettingsView.swift
git commit -m "feat: 設定に Launch at login トグルを追加（SMAppService）"
```

---

## 完了の定義

- `xcodebuild build` 成功、既存56テストが緑
- 手動確認（Task 1 Step 5）で ON/OFF によりログイン項目が増減し、自動起動が切り替わる
- デプロイメントターゲット macOS 14・既存機能・diff ロジックは無変更
