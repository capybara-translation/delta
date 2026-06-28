# Delta 選択文字のコードポイント表示 設計 (2026-06-28)

A/B の入力欄で選択中（または直前）の文字の Unicode コードポイントを各欄の下に表示する。符号化（NFC/NFD 等）の違いを直接確認できるようにする。

前提: side-by-side 表示・スカラー敏感 diff が `main` に実装済み。入力欄は現在 SwiftUI `TextEditor`（`Delta/Views/DiffEditorView.swift`）。

## 背景・動機

スカラー敏感 diff で符号化違いを検出できるようになったが、「どの文字がどのコードポイントか」を入力時点で確認したい。macOS 14 の SwiftUI `TextEditor` は選択範囲を取得する API を持たないため、AppKit の `NSTextView` をラップして選択を取得する。

## ゴール

A/B 入力欄で、選択中の文字（未選択ならカーソル直前の1書記素）の Unicode コードポイントを各欄の下に表示する。

**成功基準**: ベトナム語「ờ」を選択すると、NFC なら `U+1EDD …`、NFD なら `U+006F U+031B U+0300` が表示される。`CodePointFormatter` の単体テストが緑。既存テストも緑（リグレッションなし）。

## 主要な設計判断

| 項目 | 決定 | 理由 |
|---|---|---|
| 選択取得 | AppKit `NSTextView` を `NSViewRepresentable` でラップ | macOS 14 の `TextEditor` は選択 API がない。デプロイメントターゲットは 14 維持。 |
| 表示位置 | 各入力欄（A/B）の下に1行 | 両欄の選択を個別に確認できる。 |
| 表示内容 | 選択範囲の全スカラー。未選択時はカーソル直前1書記素 | 「選択中の文字」を確認する用途に合致。 |
| 表記 | 各スカラー `U+XXXX`。ちょうど1スカラーのとき Unicode 名も併記 | 1文字選択時は名前で分かりやすく、複数時は簡潔に。 |
| ロジック分離 | 表示文字列の生成を純粋関数 `CodePointFormatter` に分離 | テスト可能にする。View から切り離す。 |

## コンポーネント

| ファイル | 役割 |
|---|---|
| `Delta/Models/CodePointFormatter.swift`（新規） | 純粋。`describe(_ text: String) -> String`。選択文字列 → 表示文字列。 |
| `Delta/Views/CodePointTextView.swift`（新規） | `NSViewRepresentable`。`NSTextView` をラップし text を双方向同期、選択変更を報告。 |
| `Delta/Views/DiffEditorView.swift`（修正） | `TextEditor` を `CodePointTextView` に置換し、各欄の下に表示行を追加。 |

`DiffWindowView` / `SplitDiffView` / `DiffCellView` / `DiffEngine` / `DiffWindowManager` / `DeltaApp` は無変更。

### CodePointFormatter（純粋・テスト可）

```swift
enum CodePointFormatter {
    static let maxScalars = 24
    static func describe(_ text: String) -> String
}
```

仕様:
- 入力のユニコードスカラー列を取る。空なら `""`。
- 各スカラーを `U+%04X`（最小4桁、4桁超はそのまま）で表記し、半角空白で連結。
- スカラーがちょうど1個のとき、`Unicode.Scalar.Properties.name` を空白区切りで併記（名前が nil/空なら付けない）。
- スカラー数が `maxScalars` を超える場合、先頭 `maxScalars` 個＋` … (+N)`（N = 残り数）。

### CodePointTextView（AppKit ラップ）

- `@Binding var text: String`、`var onSelectionChange: (String) -> Void`。
- `NSScrollView` + `NSTextView`（等幅フォント、リッチテキスト無効、各種自動置換無効、undo 有効、bezel ボーダー）。
- delegate（`NSTextViewDelegate`）:
  - `textDidChange`: `parent.text = textView.string` し、選択を報告。
  - `textViewDidChangeSelection`: 選択を報告。
- 選択の報告内容:
  - `selectedRange().length > 0` のとき: `NSString.substring(with:)` で選択テキスト。
  - 未選択（length 0）かつ `location > 0` のとき: `rangeOfComposedCharacterSequence(at: location - 1)` で**直前の1書記素**を取り、その文字列。
  - それ以外（先頭でのカーソル）: `""`。
- `updateNSView`: ループ防止に `if textView.string != text { textView.string = text }`。

注: `NSTextView` は UTF-16。`selectedRange`/`substring(with:)`/`rangeOfComposedCharacterSequence` はいずれも UTF-16 インデックスで一貫。結合文字・サロゲートペアは `rangeOfComposedCharacterSequence` が書記素として正しく扱う。

### DiffEditorView（修正）

- `@State private var infoA = ""`、`@State private var infoB = ""` を保持。
- A/B それぞれ `CodePointTextView(text: $textX) { selected in infoX = CodePointFormatter.describe(selected) }`。
- 入力欄の下に `Text(infoX)`（等幅 caption、1行、末尾省略、`maxWidth: .infinity` 左寄せ、空なら高さ確保のため半角空白）。

## リスク・代替案

- **[MED] `NSViewRepresentable` のテキスト同期ループ/カーソル飛び**: `updateNSView` の `!=` ガードで抑止。手動確認で検証。
- **[MED] `Unicode.Scalar.Properties.name` の値**: 割り当て済み文字の名前は Unicode 規格で安定。テストで `U+0041`→`LATIN CAPITAL LETTER A`、`U+1EDD`→`LATIN SMALL LETTER O WITH HORN AND GRAVE` をアサート。
- **[LOW] 高頻度の選択変更**: `describe` は軽量。巨大選択は 24 で打ち切り。
- **代替案（不採用）**: デプロイメントターゲットを macOS 15 に上げ SwiftUI `TextEditor` の選択バインディングを使う → コードは簡潔だが対応 OS が狭まるため不採用。共有の下部ステータス行1本 → 各欄個別表示の要望により不採用。

## テスト・検証計画

`CodePointFormatter.describe` を TDD で単体テスト:
- `""` → `""`
- `"A"` → `"U+0041 LATIN CAPITAL LETTER A"`
- `"\u{1EDD}"` → `"U+1EDD LATIN SMALL LETTER O WITH HORN AND GRAVE"`
- `"\u{006F}\u{031B}\u{0300}"` → `"U+006F U+031B U+0300"`
- `"AB"` → `"U+0041 U+0042"`
- 25スカラー（例: `String(repeating: "a", count: 25)`）→ 先頭24個の `U+0061` ＋ ` … (+1)`

`CodePointTextView` / `DiffEditorView` は UI のためビルド＋手動確認:
- 「ờ」選択で NFC=`U+1EDD …` / NFD=`U+006F U+031B U+0300`
- 未選択でカーソル直後の直前1文字が出る
- 入力・カーソル移動でカーソルが飛ばない
- 既存の diff 実行・side-by-side が動く

## スコープ外

- デプロイメントターゲットの変更（macOS 14 維持）
- 共有ステータス行（各欄個別で確定）
- コードポイントのコピー機能・クリック操作
- ホットキー・履歴・設定画面
