# Delta 実行履歴 設計 (2026-06-28)

Compare 実行時の入力（textA/textB）を履歴として保持し、ポップオーバーから過去の入力を呼び戻せるようにする。

前提: メニューバー常駐アプリ。diff 入力は `DiffWindowView`（`textA`/`textB` は `@AppStorage`）。元設計メモ（`docs/Delta.md`）の推奨順 5 に相当。

## 背景・動機

過去に比較した入力をすぐ呼び戻せると、繰り返しの差分確認が速くなる。元メモの「実行履歴を 30 件程度保持、各エントリ id/timestamp/textA/textB、`@Observable` Store＋UserDefaults JSON」を実装する。

## ゴール

Compare 実行時に入力を履歴へ記録し、ツールバーの「History」ボタンのポップオーバーから一覧・選択して `textA`/`textB` を読み戻せるようにする。履歴は最大30件、再起動後も復元する。

**成功基準**: Compare すると履歴が増える（直前と同一内容・両方空は除く）。History ポップオーバーからエントリを選ぶと A/B に読み込まれる。Clear で消える。再起動後も復元。`HistoryStore` の単体テストが緑。既存テストも緑。

## 主要な設計判断

| 項目 | 決定 | 理由 |
|---|---|---|
| UI | ツールバーの「History」ボタン＋ポップオーバー | 同じウィンドウで素早く呼び戻せる。 |
| 記録タイミング | Compare 実行時 | 「実行履歴」。 |
| 重複・空の扱い | 両方空は記録しない／直前エントリと textA・textB が完全一致なら追加しない | 連打スパム防止。 |
| 並び・上限 | 新しい順に先頭追加、最大30件（超過は最古を削除） | 元メモの上限。 |
| 読み戻し | 選択で textA/textB をエディタに入れるのみ（再実行しない） | 中身を確認してから Compare できる。 |
| label メモ | 含めない | YAGNI。 |
| 永続化 | `@Observable` ストア＋UserDefaults に JSON | 元メモ準拠。`@Observable` は macOS 14+。 |
| テスト容易性 | `add(date:)` を引数注入、`UserDefaults` を注入可能に | ロジックを決定的にテスト。 |

## コンポーネント

| ファイル | 役割 |
|---|---|
| `Delta/Models/HistoryEntry.swift`（新規） | 履歴エントリのモデル。 |
| `Delta/Store/HistoryStore.swift`（新規） | `@Observable` ストア。追加・消去・永続化。 |
| `Delta/Views/HistoryView.swift`（新規） | ポップオーバー内容（一覧・選択・Clear・空状態）。 |
| `Delta/Views/DiffWindowView.swift`（修正） | History ボタン＋popover、ストア保持、Compare 時の記録、選択時の読み戻し。 |

`DiffEngine`・`CodePointTextView`・`DiffEditorView`・`SplitDiffView`・`DiffCellView`・`DiffWindowManager`・`GlobalHotKey`・`SettingsView`・`CodePointFormatter`・`TabKeyResolver` は無変更。

### HistoryEntry

```swift
import Foundation

struct HistoryEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let textA: String
    let textB: String
}
```

### HistoryStore（`@Observable`、テスト可）

```swift
import Foundation
import Observation

@Observable
final class HistoryStore {
    private(set) var entries: [HistoryEntry]
    static let maxEntries = 30

    init(userDefaults: UserDefaults = .standard, key: String = "history")
    func add(textA: String, textB: String, date: Date)
    func clear()
}
```

仕様:
- `init`: 指定 `UserDefaults` の `key` から JSON をデコードして `entries` を復元（無ければ空）。
- `add`:
  - `textA` と `textB` が両方空 → 何もしない。
  - 既存先頭（最新）エントリの `textA`・`textB` が引数と完全一致 → 何もしない。
  - それ以外 → `HistoryEntry(id: UUID(), timestamp: date, textA:, textB:)` を**先頭に挿入**。
  - `entries.count > maxEntries` なら末尾（最古）を削除して30件に保つ。
  - 変更後、JSON エンコードして `UserDefaults` に保存。
- `clear`: `entries = []` にして保存。
- 永続化は `JSONEncoder`/`JSONDecoder`。

### HistoryView（ポップオーバー）

- `store: HistoryStore`、`onSelect: (HistoryEntry) -> Void` を受け取る。
- ヘッダに「Clear」ボタン（`store.clear()`）。
- `entries` が空なら「No history」を表示。
- `List(store.entries)` で各行: 日時（`timestamp` を簡潔表記）＋`textA`/`textB` のプレビュー（1行・末尾省略）。行タップで `onSelect(entry)`。
- 適度な固定サイズ（例: 幅 360・高さ 320）。

### DiffWindowView（修正）

- `@State private var history = HistoryStore()` を保持。
- ツールバー HStack に「History」ボタンを追加し、`.popover(isPresented:)` で `HistoryView(store: history) { entry in textA = entry.textA; textB = entry.textB; <close popover> }`。
- `run()` の末尾で `history.add(textA: textA, textB: textB, date: Date())`。
- 既存の Picker（Horizontal/Vertical）・Compare・`SplitDiffView`・コードポイント表示は不変。

## リスク

- **[MED] `@Observable`＋`@State`／`.popover` の標準パターン**: 所有と再描画。手動確認で検証。
- **[LOW] UserDefaults JSON の肥大**: 30件×2テキスト。巨大テキストでは肥大しうる。通常用途では許容。必要なら後で SwiftData 移行や本文長制限。
- **[LOW] timestamp 表示**: ロケール依存の簡潔表記で十分。

## テスト・検証計画

`HistoryStore` を TDD で単体テスト（注入 `UserDefaults(suiteName:)`・`date` 固定で決定的）:
- `add` で先頭追加（新しい順）
- 直前と textA/textB 完全一致なら追加しない
- 両方空なら追加しない
- 上限30: 31件目で最古削除（件数30維持）
- 連続でない重複（最新以外と同じ）は追加される
- 永続化往復: 同じ defaults で新ストアを作ると復元
- `clear()` で空＋永続化も空
- `add(date:)` 注入で `timestamp` を検証

`HistoryView`/`DiffWindowView` は UI のためビルド＋手動確認:
- Compare で履歴増加／同一連打で増えない／両方空で増えない
- History ボタン → 一覧、選択で A/B 読み込み（再実行なし）
- Clear で消える／再起動後も残る
- 既存の diff・コードポイント・Tab・⌃⌥D・設定が動く

既存39テスト＋新規ストアテストが緑（リグレッションなし）。

## スコープ外

- label メモ・エントリ編集
- 履歴の検索・お気に入り・エクスポート
- SwiftData 移行（件数増加時に検討）
- エントリ選択時の自動再実行
