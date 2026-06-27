# Delta MVP 設計 (2026-06-27)

常駐型 GUI Diff ツール Delta の MVP（ドキュメント `docs/Delta.md` の推奨順 1〜2）の設計。

## ゴール

メニューバー常駐の Delta を、次の状態まで動かす:

> メニューバーから小窓を開く → 左右にテキストを入力 → 実行 → ユニファイドのカラー diff 表示（行/文字 切替）

**成功基準**: `xcodebuild` でビルドが通り、メニューバーからウィンドウを開いてサンプルテキストの差分が緑/赤で色付き表示される。`DiffEngine` の単体テストが緑。

## スコープ

### 含む（MVP）
- メニューバー常駐（`MenuBarExtra`）＋メニューからウィンドウ表示
- 左右2つのテキスト入力ボックス
- 実行ボタン（⌘↵）でカラー diff 表示（追加=緑背景 / 削除=赤背景）
- diff 粒度の切替: **行単位** / **文字単位（grapheme）**

### 含まない（次セッション以降）
- グローバルホットキー（ドキュメント手順 3）
- 設定の永続化（手順 4、`@AppStorage`）
- 履歴（手順 5、`@Observable` Store + UserDefaults）
- UI 微調整（手順 6）

## 主要な設計判断

| 項目 | 決定 | 理由 |
|---|---|---|
| プロジェクト形式 | XcodeGen (`project.yml`) | 宣言的で差分が読みやすく保守性が高い。`brew install xcodegen` が必要。 |
| 対応 macOS | macOS 14 (Sonoma)+ | `MenuBarExtra` 等のモダン SwiftUI API を使いつつワン世代前まで互換。後続フェーズの `@Observable`（macOS 14+）も見据える。 |
| 結果レイアウト | ユニファイド（1列） | git diff 風。シンプルで幅を取らない。 |
| 細粒度モード | **文字単位（grapheme cluster）** | **日本語は語間に空白がなく空白 split が機能しない**ため、`Character` 列で diff。言語非依存・決定的・テスト容易。絵文字/結合文字も安全。 |
| diff アルゴリズム | Swift 標準 `CollectionDifference` | 依存ゼロで十分。不満が出たら自前 Myers に差し替え。 |
| 状態管理 | `DiffWindowView` の `@State` | MVP は永続化なし。Store 層は設定/履歴フェーズで導入（YAGNI）。 |
| テスト | Swift Testing（Xcode 16+ 同梱） | 簡潔。問題が出れば XCTest にフォールバック。 |
| アプリ種別 | `LSUIElement=true` | Dock 非表示の純メニューバーアプリ。 |
| Bundle ID | `com.capybara.delta` | ドキュメント準拠。 |

## アーキテクチャ / 構成

```
delta/
├── project.yml                 ← XcodeGen 定義（Delta app + DeltaTests）
├── Delta/
│   ├── DeltaApp.swift          ← @main, MenuBarExtra + Window scene
│   ├── Info.plist              ← LSUIElement=true
│   ├── Views/
│   │   ├── DiffWindowView.swift   ← 入力＋モード切替＋実行＋結果のまとめ（@State 保持）
│   │   ├── DiffEditorView.swift   ← 左右テキスト入力
│   │   └── DiffResultView.swift   ← カラー diff 描画
│   └── Models/
│       └── DiffEngine.swift       ← 純粋関数。行/文字の diff 計算（UI 非依存）
├── DeltaTests/
│   └── DiffEngineTests.swift   ← DiffEngine の単体テスト（Swift Testing）
├── README.md
└── .gitignore
```

### DiffEngine（要、UI 非依存）

純粋ロジックとして分離し単体テスト可能にする。これが品質の核。

- 入力: `textA: String`, `textB: String`, `mode: DiffMode`（`.line` / `.character`）
- 出力: 描画用の構造化結果（`[DiffSegment]` 等）。各セグメントは内容と種別（`.equal` / `.insert` / `.delete`）を持つ。
- 行モード: `split(separator: "\n", omittingEmptySubsequences: false)` で行配列にし `CollectionDifference` を取る。末尾改行差も区別できるよう空サブシーケンスは省略しない。
- 文字モード: `Array(text)`（`Character` = 書記素クラスタ列）で `CollectionDifference` を取る。日本語・絵文字・結合文字に対応。
- ユニファイド再構成: `CollectionDifference` の removals/insertions と共通要素から、削除→挿入→共通の順で1列のセグメント列を組み立てる。

### View 層

- `DiffWindowView`: `@State` で `textA` / `textB` / `mode` / `result` を保持。実行で `DiffEngine` を呼び `result` を更新。
- `DiffEditorView`: `TextEditor` を左右に。`@Binding` で親の state に接続。
- `DiffResultView`: `DiffSegment` 列を受け取り、種別ごとに背景色（追加=緑 / 削除=赤 / 共通=無色）で描画。

### App / Scene

- `MenuBarExtra("Delta", systemImage: ...)`: 「Open Diff Window」「Quit」。
- `Window("Diff", id: "diff-main")`: 単一インスタンス Scene。`@Environment(\.openWindow)` で表示。
- アクセサリアプリ（`LSUIElement`）はウィンドウ表示時に `NSApplication.shared.activate(...)` で前面化が必要。

## リスクと失敗モード

- **[MED] XcodeGen / Xcode のバージョン整合**: macOS 26 + 最新 Xcode で生成プロジェクトのビルド設定が古いと警告/失敗。→ `project.yml` で `deploymentTarget: macOS 14.0` と `SWIFT_VERSION` を明示し、最小設定から増やす。
- **[MED] `MenuBarExtra` + `Window` のフォーカス/多重生成**: メニューから開いても前面に来ない。→ 単一 `Window` Scene + `openWindow(id:)` + `NSApp.activate`。
- **[MED] ビルドが CLT を参照して失敗**: `xcode-select` が CommandLineTools を指す。→ ビルドは `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild ...`（sudo 不要、システム設定不変）。README に明記。
- **[LOW] 文字モードのユニファイド再構成のズレ**: removals/insertions のインデックス基準を誤ると順序が崩れる。→ テストで固定（下記）。
- **[LOW] テスト実行**: SwiftPM ではなく Xcode テストターゲット。`DEVELOPER_DIR=... xcodebuild test -scheme Delta` を README 化。

## テスト・検証計画

`DiffEngine` をテスト先行（TDD）で実装する。

### 単体テスト（決定的・UI 非依存）
- 行モード: 追加のみ / 削除のみ / 置換 / 空文字どうし / 末尾改行差 / 完全一致（差分ゼロ）
- 文字モード: **日本語の1文字差**（`"色赤"` vs `"色青"`）/ 絵文字 / 結合文字（濁点付き）/ 片側空 / 完全一致
- 境界: 巨大入力でクラッシュしない（スモーク）

### ビルド/手動検証
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme Delta build` 成功。
- 起動 → メニューバーにアイコン → ウィンドウ表示 → サンプル diff が緑/赤で表示。

## 実装手順

1. `brew install xcodegen`、`.gitignore` 作成
2. `project.yml`（Delta アプリ＋DeltaTests、macOS 14、LSUIElement、Bundle ID）
3. `DiffEngine`（テスト先行: 失敗テスト→実装→緑）
4. `DeltaApp` + `MenuBarExtra` + `Window`（ビルド＆起動確認）
5. `DiffWindowView` / `DiffEditorView` / `DiffResultView`（入力→実行→着色表示）
6. `README`（ビルド/実行手順、`DEVELOPER_DIR` 注記）
