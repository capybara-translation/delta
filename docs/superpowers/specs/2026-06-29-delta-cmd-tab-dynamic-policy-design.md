# Delta Diff Cmd+Tab 動的アクティベーションポリシー 設計 (2026-06-29)

Diff ウィンドウを開いている間だけ通常アプリ（`.regular`）になり、Cmd+Tab と Dock に現れるようにする。閉じている間はメニューバー常駐（accessory）のまま。

前提: メニューバー常駐アプリ（`LSUIElement: true`）。ウィンドウは AppKit 管理の `DiffWindowManager`。

## 背景・動機

メニューバー常駐（accessory）アプリは Cmd+Tab に現れない。macOS では Cmd+Tab に出す＝アクティベーションポリシー `.regular` で、これは Dock アイコンも伴う（両者は分離不可）。常駐の軽さを保ちつつ Cmd+Tab を得るため、ウィンドウ表示中だけ `.regular` に切替える。

## ゴール

Diff ウィンドウ表示中は `.regular`（Dock＋Cmd+Tab に出る）、非表示時は `.accessory`（出ない）に動的切替する。

**成功基準**: ウィンドウを開くと Cmd+Tab と Dock に Delta Diff が現れ、閉じる/隠すと消える。既存機能は維持。既存テストは緑のまま。

## 主要な設計判断

| 項目 | 決定 | 理由 |
|---|---|---|
| 方式 | 動的切替（表示中のみ `.regular`） | 常駐の軽さを保ちつつ Cmd+Tab を得る。常時 `.regular` だと Dock アイコンが常駐する。 |
| 起動時 | `LSUIElement: true` を維持（accessory 起動） | 起動時は Dock なし。 |
| 切替箇所 | `DiffWindowManager` の show/hide ＋ `windowWillClose` | 表示/非表示/閉じるを一元管理。 |

## コンポーネント

| ファイル | 役割 |
|---|---|
| `Delta/Window/DiffWindowManager.swift`（修正） | `NSObject, NSWindowDelegate` 化。表示で `.regular`、非表示/閉じるで `.accessory`。 |

`LSUIElement: true` は維持。`project.yml`・他ファイルは無変更。

### DiffWindowManager（修正）

- クラスを `@MainActor final class DiffWindowManager: NSObject, NSWindowDelegate` にする（delegate になるため NSObject 化）。`private override init() { super.init() }`。
- `show()`:
  - 初回生成時に `newWindow.delegate = self` を設定。
  - `NSApp.setActivationPolicy(.regular)` を呼んでから、既存の `makeKeyAndOrderFront(nil)` ＋ `NSApplication.shared.activate(ignoringOtherApps: true)`。
- `hide()`（新設・private）: `window?.orderOut(nil)` のあと `NSApp.setActivationPolicy(.accessory)`。
- `toggle()`: 表示中かつ key window なら `hide()`、それ以外は `show()`。
- `windowWillClose(_:)`: `NSApp.setActivationPolicy(.accessory)`（赤ボタン/⌘W での閉じる対応。`orderOut` はこの通知を発火しないため hide() 側でも明示処理する）。

## リスク

- **[MED] `orderOut` は `windowWillClose` を発火しない**: ⌃⌥D の hide 経路では `hide()` 内で明示的に `.accessory` にする（対応済み）。
- **[LOW] `.regular` 化で標準アプリメニューが付く**: macOS の仕様。許容。
- **[LOW] 切替時のちらつき**: 軽微。

## テスト・検証計画

AppKit のアクティベーションポリシー挙動で純粋ロジックが無く自動テストは作れない。**ビルド＋手動確認**で検証する。

手動確認:
- ウィンドウを開く → Cmd+Tab と Dock に Delta Diff が現れる
- 赤ボタン/⌘W で閉じる → Cmd+Tab/Dock から消える
- ⌃⌥D で隠す → 消える、再度 ⌃⌥D で出す → 現れる
- メニューバー δ・diff 実行・Settings・履歴・⌃⌥D・前面化が引き続き動く

自動テスト:
- 既存56テストが緑のまま（リグレッションなし）。新規テストは追加しない（AppKit 統合のため）。

## スコープ外

- 常時通常アプリ化（Dock 常駐）
- アプリメニューのカスタマイズ
- Dock アイコン画像（既定アイコン）
