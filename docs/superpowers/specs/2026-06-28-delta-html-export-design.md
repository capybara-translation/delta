# Delta Diff HTML エクスポート 設計 (2026-06-28)

比較結果を、現在の表示向きに追従した自己完結 HTML ファイルとして書き出す。

前提: side-by-side 表示（`SplitDiffView`）と diff 結果 `rows: [DiffRow]`、向き `orientation: SplitOrientation` が `DiffWindowView` にある。

## 背景・動機

比較結果を共有・保存したいときに、色付きの diff をそのまま HTML ファイルに出力できると便利。アプリ外でブラウザで開ける自己完結ファイルにする。

## ゴール

ツールバーの Export ボタンから、現在の比較結果を **現在の表示向きに追従した色付き HTML** として保存ダイアログ経由で書き出す。

**成功基準**: Compare 後に Export → 保存した `.html` をブラウザで開くと、アプリと同じ色付き diff（向きも一致）が表示される。`HTMLExporter` の単体テストが緑。既存テストも緑。

## 主要な設計判断

| 項目 | 決定 | 理由 |
|---|---|---|
| トリガー | ツールバーの Export ボタン（`rows` 非空で有効） | Compare の隣で素早く出力。 |
| 保存 | `NSSavePanel`（`.html`、既定名 `delta-diff.html`） | macOS 標準の保存ダイアログ。 |
| レイアウト | 現在の `orientation` に追従（Horizontal=2列表 / Vertical=A 上・B 下） | アプリの見た目と一致させる。 |
| 内容 | カラー diff のみ＋生成日時ヘッダ。自己完結（CSS インライン） | 外部依存なしで単体配布可。 |
| ロジック分離 | `HTMLExporter`（純粋関数）で HTML 文字列を生成 | テスト可能にし、保存（AppKit）から切り離す。 |

## コンポーネント

| ファイル | 役割 |
|---|---|
| `Delta/Models/HTMLExporter.swift`（新規） | 純粋。`rows`＋`orientation`＋`generatedAt` から完結 HTML 文字列を生成。 |
| `Delta/Views/DiffWindowView.swift`（修正） | Export ボタン、`NSSavePanel`、`HTMLExporter.html(...)` の書き出し。 |

`DiffEngine`・`SplitDiffView`・`DiffCellView`・`CodePointTextView`・`HistoryStore`・`HistoryView`・`SettingsView`・`DiffWindowManager`・`GlobalHotKey` は無変更。

### HTMLExporter（純粋・テスト可）

```swift
import Foundation

enum HTMLExporter {
    static func html(rows: [DiffRow], orientation: SplitOrientation, generatedAt: Date) -> String
}
```

HTML 構造:
- `<!DOCTYPE html>` ＋ `<head>` に `<meta charset="utf-8">`、`<title>Delta Diff</title>`、インライン `<style>`。
- `<style>`: monospace フォント、`white-space: pre`（空白保持）、`.ins { background:#ccffd8 }`、`.del { background:#ffd7d5 }`、`.gap { background:#f0f0f0 }`、表/セルの枠線・余白。
- ヘッダ: 生成日時を表示する小さな要素（例 `<p class="meta">Generated: ...</p>`）。
- 本体（向き別）:
  - **Horizontal**: `<table class="diff h">` 各行 `<tr><td>左セル</td><td>右セル</td></tr>`。
  - **Vertical**: `<div class="diff v">` 内に `<div class="pane">`（全行の左セル）＋`<div class="pane">`（全行の右セル）。

セル描画規則（`DiffCellView` を踏襲）:
- `nil`（ギャップ）→ `gap` クラスの空行（高さ確保のため `&nbsp;` 等）。
- 単一の非 equal セグメント（行全体の追加/削除）→ セル要素に `ins`/`del` クラス（背景全体）、テキストは素。
- それ以外（equal 単独 or 行内混在）→ 各セグメントをエスケープし、`.insert`→`<span class="ins">`、`.delete`→`<span class="del">`、`.equal`→素のテキストで連結。
- すべての可視テキストは HTML エスケープ（`&`→`&amp;`、`<`→`&lt;`、`>`→`&gt;`）。

### DiffWindowView（修正）

- ツールバー HStack に **Export** ボタンを追加（`.disabled(rows.isEmpty)`）。
- アクション:
  ```swift
  let panel = NSSavePanel()
  panel.allowedContentTypes = [.html]
  panel.nameFieldStringValue = "delta-diff.html"
  if panel.runModal() == .OK, let url = panel.url {
      let html = HTMLExporter.html(rows: rows, orientation: orientation, generatedAt: Date())
      try? html.write(to: url, atomically: true, encoding: .utf8)
  }
  ```
  `import AppKit` / `import UniformTypeIdentifiers` を追加。
- 既存の Picker・History・Compare・`SplitDiffView` は不変。

## リスク

- **[LOW] 巨大入力で HTML 肥大**: 通常用途では許容。
- **[LOW] 保存失敗の握りつぶし**: `try?` でエラーを無視。必要なら後でアラート表示。
- **[LOW] `NSSavePanel.runModal()` のモーダル**: メインスレッドで実行（ボタンアクションは main）。

## テスト・検証計画

`HTMLExporter.html` を TDD で単体テスト（`generatedAt` 注入・主要構造/部分文字列でアサート）:
- HTML エスケープ（`<`,`&`,`>` → `&lt;`/`&amp;`/`&gt;`）
- Horizontal: `<table` と行数分の `<tr>`/`<td>`
- Vertical: 2つの `pane`
- 行内ハイライト: `<span class="del">`/`<span class="ins">`
- 行全体追加/削除: セルに `ins`/`del` クラス
- ギャップ（nil）: `gap` クラス
- ヘッダに `generatedAt` 表記
- 完結ドキュメント（`<!DOCTYPE html>` と `<style>` を含む）

`Export` ボタン＋`NSSavePanel`＋書き出しは UI のためビルド＋手動確認:
- Compare 後 Export → 保存 → ブラウザで開くとアプリと同じ色付き diff（向き一致）
- 結果なしのとき Export は無効
- 既存の diff・履歴・設定・Tab・⌃⌥D が動く

既存48テスト＋新規 Exporter テストが緑（リグレッションなし）。

## スコープ外

- 原文 A/B の別セクション出力（カラー diff のみ）
- PDF/画像など他形式
- スタイルのカスタマイズ UI
- 保存失敗時のアラート表示（必要なら後追い）
