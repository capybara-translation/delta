# Delta 設定の永続化（テキスト保持） 設計 (2026-06-28)

「入力テキストを再起動後も残す / 毎回空から始める」を設定で切り替え、標準の設定ウィンドウ（⌘,）で操作できるようにする。

前提: メニューバー常駐アプリ。入力欄テキストは現在 `DiffWindowView` の `@State`。元設計メモ（`docs/Delta.md`）の推奨順 4 に相当。

## 背景・動機

ウィンドウは常駐するためセッション中はテキストが残るが、アプリ再起動でリセットされる。「前回のテキストを残す」か「毎回クリア」かを選べるようにし、設定基盤（標準設定ウィンドウ）を整える。

## ゴール

設定トグル「Keep text between launches」（既定 ON）で、入力テキスト `textA`/`textB` を再起動後も復元するか、毎回空から始めるかを切り替える。設定は標準の設定ウィンドウ（⌘,）で操作する。

**成功基準**: ON でテキストを入力して再起動すると復元される。OFF にして再起動すると空で始まる。⌘, またはメニュー「Settings…」で設定ウィンドウが開く。既存テストは緑のまま。

## セマンティクス（確定）

- `keepTextOnReopen`（`@AppStorage`、既定 `true`）。
- **ON**: `textA`/`textB` を UserDefaults に保存し、再起動後に復元する。
- **OFF**: アプリ起動時に `textA`/`textB` をクリアし、毎回空から始める。セッション中はウィンドウが常駐するためテキストは保持される（「毎回クリア」＝「起動のたびに空」と解釈）。

## 主要な設計判断

| 項目 | 決定 | 理由 |
|---|---|---|
| 保存 | `@AppStorage`（UserDefaults）をビューで直接利用 | 元メモ準拠。`SettingsStore` クラスは作らない（YAGNI）。 |
| テキスト永続化 | `textA`/`textB` を `@State` → `@AppStorage` に変更 | 再起動をまたいだ保持を最小変更で実現。`$textA` の Binding はそのまま利用可。 |
| OFF 時のクリア | 起動時（`applicationDidFinishLaunching`）に `textA`/`textB` キーを削除 | 「起動のたびに空」を一箇所で実現。表示/非表示ごとには消さない。 |
| 設定 UI | SwiftUI `Settings` シーン＋`SettingsLink` | macOS 標準の設定ウィンドウ（⌘,）。拡張しやすい。 |
| ホットキー設定 | 今回スコープ外 | キー録画 UI は別途。テキスト保持に集中。 |

## コンポーネント

| ファイル | 役割 |
|---|---|
| `Delta/Views/SettingsView.swift`（新規） | `Form` に Toggle「Keep text between launches」。`@AppStorage("keepTextOnReopen")` に直結。 |
| `Delta/DeltaApp.swift`（修正） | `Settings { SettingsView() }` シーンを追加。MenuBarExtra に `SettingsLink { Text("Settings…") }` を追加。`AppDelegate` で OFF 時の起動時クリア。 |
| `Delta/Views/DiffWindowView.swift`（修正） | `textA`/`textB` を `@AppStorage` に変更。 |

`DiffEngine`・`SplitDiffView`・`DiffCellView`・`CodePointTextView`・`DiffEditorView`・`DiffWindowManager`・`GlobalHotKey` は無変更。

### SettingsView（新規）

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

### DeltaApp（修正）

- `body` に `Settings { SettingsView() }` シーンを追加（既存 `MenuBarExtra` と並列）。
- MenuBarExtra のメニューに `SettingsLink { Text("Settings…") }` を「Open Diff Window」と Divider/Quit の間に追加。
- `AppDelegate.applicationDidFinishLaunching`（既存。ホットキー登録と同じ）に、OFF 時のクリアを追加:
  ```swift
  let keep = UserDefaults.standard.object(forKey: "keepTextOnReopen") as? Bool ?? true
  if !keep {
      UserDefaults.standard.removeObject(forKey: "textA")
      UserDefaults.standard.removeObject(forKey: "textB")
  }
  ```
  既定値の扱い: キー未設定（初回起動）は `true`（保持）として扱う。

### DiffWindowView（修正）

```swift
@AppStorage("textA") private var textA = ""
@AppStorage("textB") private var textB = ""
```
それ以外（`orientation`/`rows`/`run()`、`DiffEditorView`/`SplitDiffView` への受け渡し）は不変。`$textA`/`$textB` の Binding は `@AppStorage` の projectedValue としてそのまま `CodePointTextView`（AppKit ラップ）に渡せる。

## リスク

- **[MED] `@AppStorage` の書き込み負荷**: 1キーストロークごとに文字列全体を UserDefaults に書き込む。巨大テキストでは負荷になりうる。通常の差分確認用途では許容。必要なら後でデバウンス/別ストア化。
- **[LOW] API 可用性**: `Settings` シーン・`SettingsLink` は macOS 14+。対象内。
- **[LOW] OFF→ON の切替タイミング**: クリアは起動時のみ。セッション中に OFF にしても即時クリアはしない（次回起動から空）。仕様として明記。

## テスト・検証計画

`@AppStorage` 配線と設定 UI が中心で、意味のある単体テスト（判定は `!keepText` のみ）は作らない。**ビルド＋手動確認**で検証する。

手動確認:
- ON（既定）でテキスト入力 → 終了・再起動 → テキストが復元
- OFF にして終了・再起動 → 空で始まる
- ⌘, またはメニュー「Settings…」で設定ウィンドウが開き、Toggle が効く
- 既存の diff 実行・side-by-side・コードポイント表示・Tab・⌃⌥D が動く

自動テスト:
- 既存39テストが緑のまま（リグレッションなし）を確認。新規テストは追加しない。

## スコープ外

- ホットキーのカスタマイズ UI（別ステップ）
- 履歴（推奨順 5）
- テキスト以外の設定項目
- `@AppStorage` のデバウンス/別ストア化
