# Delta Diff コードポイントの全件コピー 設計 (2026-07-01)

コードポイント表示欄を右クリックし、選択文字の**全コードポイント**（表示は切り詰めのまま）をクリップボードにコピーできるようにする。

前提: 各入力ボックス下に、選択中文字のコードポイントを `U+XXXX …` 形式で表示している（`DiffEditorView` ＋ `CodePointFormatter`）。表示は `CodePointFormatter.maxScalars`(=24) を超えると `… (+N)` で切り詰める。表示 `Text` は `.textSelection(.enabled)` だが、選択コピーで得られるのも切り詰め後の文字列。

## 背景・動機

長い選択でも表示は省略で問題ないが、コピー時は**全コードポイントを取得したい**（バグ報告や共有のため）。現状は表示＝コピー対象が同一（切り詰め）で、全件を取り出す手段がない。

## ゴール

コードポイント表示欄のコンテキストメニューから「Copy code points」で、選択中文字の**全スカラー**を `U+XXXX …` 形式（表示と同じ体裁・切り詰めなし）でクリップボードにコピーできる。

**成功基準**:
- 24 スカラーを超える選択でも、コピー結果に全スカラーが含まれる（`… (+N)` を含まない）。
- 表示欄の見た目（切り詰め）は変わらない。
- 選択が空のときはメニュー項目が無効。
- 既存機能・既存テストは維持。

## 主要な設計判断

| 項目 | 決定 | 理由 |
|---|---|---|
| 起動 UI | コードポイント `Text` のコンテキストメニュー | 省スペースな行を邪魔しない。macOS 的。 |
| コピー形式 | 表示と同じ `U+XXXX …`（スペース区切り、1 スカラー時は名前付き）を切り詰めなしで | 「表示の完全版」で一貫。 |
| 生成 | `CodePointFormatter` に切り詰めなし版 `fullList` を追加 | 表示用 `describe` と責務分離。純粋関数でテスト可能。 |
| 状態 | 各ボックスの生の選択文字列を保持し、表示・コピーとも派生 | 単一の真実（選択文字列）から表示（切り詰め）とコピー（全件）を導出。 |

## コンポーネント

| ファイル | 役割 |
|---|---|
| `Delta/Models/CodePointFormatter.swift`（修正） | `fullList(_:) -> String` を追加（切り詰めなしの全スカラー列）。`hex`・単一スカラー名付与を `describe` と共有。 |
| `Delta/Views/DiffEditorView.swift`（修正） | 各ボックスの生の選択を `@State` 保持。表示は `describe`、右クリックで `fullList` を `NSPasteboard` にコピー。`import AppKit`。 |
| `DeltaTests/CodePointFormatterTests.swift`（新規または追記） | `fullList` の単体テスト。 |

### CodePointFormatter（修正）

- 既存 `describe(_:)`（切り詰めあり）は変更しない。
- 追加:
  ```swift
  /// Lists every scalar as U+XXXX (space-separated), never truncating.
  /// When there is exactly one scalar, appends its Unicode name (same as describe).
  /// Empty input returns an empty string.
  static func fullList(_ text: String) -> String {
      let scalars = Array(text.unicodeScalars)
      if scalars.isEmpty { return "" }
      var parts = scalars.map(hex)
      if scalars.count == 1, let name = scalars[0].properties.name, !name.isEmpty {
          parts[0] += " " + name
      }
      return parts.joined(separator: " ")
  }
  ```
- `hex(_:)` は既存の private 実装を共用（`describe` と同じ体裁）。

### DiffEditorView（修正）

- 状態を「表示用の整形済み文字列」から「生の選択文字列」に変更:
  - `@State private var selectionA: String = ""` / `selectionB: String = ""`。
- `editor(...)` ヘルパは `selection: Binding<String>` を受け取る:
  - `CodePointTextView` のコールバックで `selection.wrappedValue = selected`。
  - 表示: `let display = CodePointFormatter.describe(selection.wrappedValue)` を `Text` に（空なら従来どおり `" "`）。
  - `Text` に付与:
    - 既存の `.font/.foregroundStyle/.lineLimit(1)/.truncationMode(.tail)/.frame/.textSelection(.enabled)` は維持。
    - `.contextMenu { Button("Copy code points") { copy(selection.wrappedValue) }.disabled(selection.wrappedValue.isEmpty) }`。
- コピー処理:
  ```swift
  private func copyCodePoints(_ selected: String) {
      let full = CodePointFormatter.fullList(selected)
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(full, forType: .string)
  }
  ```
- `import AppKit`（`NSPasteboard`）を追加。

## データフロー

```
選択変更: CodePointTextView コールバック → selectionA/B（生の選択）を更新
表示:     Text ← CodePointFormatter.describe(selection)   （切り詰めあり・従来通り）
コピー:   右クリック → Copy code points → CodePointFormatter.fullList(selection) → NSPasteboard
```

## エッジケース

- **空選択**: `fullList("") == ""`。メニュー項目は `.disabled`。
- **1 スカラー**: 名前付き（`describe` と同一体裁）。
- **maxScalars 超**: `describe` は `… (+N)` で切り詰め、`fullList` は全件。両者を対比するテストを置く。
- **サロゲート/結合文字**: `unicodeScalars` 単位で列挙（既存 `describe` と同じ粒度）。

## テスト方針

`CodePointFormatterTests`（`import Testing`）に `fullList` の単体テストを追加:
- 空 → `""`。
- 単一スカラー（例 `"A"` → `"U+0041 LATIN CAPITAL LETTER A"`）。
- 複数スカラー（例 `"ab"` → `"U+0061 U+0062"`、名前なし）。
- `maxScalars` 超（例 30 文字）→ `fullList` は 30 件すべてを含み `…` を含まない。同入力で `describe` は `… (+` を含む、を対比。

`NSPasteboard` への書き込みと `.contextMenu` は UI/副作用のため手動確認:
- 24 スカラー超を選択 → 右クリック → Copy code points → 別アプリに貼り付けて全件（`…` なし）を確認。
- 空選択でメニューが無効。

## 非対象（YAGNI）

- コピー形式の切替（改行区切り・文字併記など）。今回は「表示の完全版」1 種のみ。
- 生の選択テキスト自体のコピー（既存の `.textSelection` で可能）。
- 表示側の切り詰め挙動の変更。
