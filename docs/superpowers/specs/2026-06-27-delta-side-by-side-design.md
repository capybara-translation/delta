# Delta 差分表示の Side-by-Side 化 設計 (2026-06-27)

Delta MVP（ユニファイド1列表示）の結果ビューを、左右2ペインの行揃え side-by-side 表示に変更する。変更行ペアの内部は文字単位でハイライトし、分割向き（左右/上下）を切替・永続化する。

前提: [Delta MVP 設計](2026-06-27-delta-mvp-design.md) のアプリ・`DiffEngine`・ビュー構成が `main` に実装済み。

## ゴール

結果表示をユニファイド1列から **左右2ペインの行揃え side-by-side** に変更する。

- 行は左右で高さを揃える（ギャップ補完）。削除行は左に赤・右は空行、追加行は右に緑・左は空行、共通行は両方。
- 変更行ペアの内部は **文字単位ハイライト**（日本語対応）。例: `色赤` vs `色青` → 左で「赤」、右で「青」だけ着色。
- **分割向きを左右/上下で切替**でき、選択は `@AppStorage` で永続化する。

**成功基準**: `xcodebuild` 成功・`DiffEngine.sideBySide` の単体テスト緑・手動確認で左右/上下それぞれ行揃えと行内ハイライトが表示される。

## 主要な設計判断

| 項目 | 決定 | 理由 |
|---|---|---|
| 結果表示 | 左右2ペイン行揃え（ギャップ補完） | 古典的 side-by-side。比較しやすい。 |
| 変更行の細粒度 | 行揃え＋行内文字ハイライト（ハイブリッド） | 1文字違いでも差分が一目で分かる。日本語の細かい差分要件を維持。 |
| 行/文字トグル | **撤去** | ハイブリッドが両者を内包し冗長になるため。代わりに左右/上下トグルを置く。 |
| 上下オプション | 2ペイン（A/B）の分割向き。A上・B下。行揃えは維持。 | 水平/垂直スプリットと同じ発想。 |
| 向きの永続化 | `@AppStorage("splitOrientation")` | レイアウト好みは保持が自然。1行で済み、設定画面は作らない。 |
| diff ロジック | 既存 `diff(_:_:mode:)` を行内 diff に再利用 | DRY。既存 API・テストを温存（破壊なし）。 |
| 行ペアリング | 隣接する削除群×挿入群を index 順にペア、余りは片側のみ | 単純で決定的。賢い LCS ペアリングは MVP には過剰（YAGNI）。 |

## データモデルと DiffEngine

`DiffEngine.swift` に追加（既存 `DiffMode`/`DiffKind`/`DiffSegment`/`diff(_:_:mode:)` は変更しない）:

```swift
struct DiffRow: Equatable {
    let left: [DiffSegment]?    // nil = この行は左に存在しない（ギャップ）
    let right: [DiffSegment]?   // nil = この行は右に存在しない（ギャップ）
}

enum DiffEngine {
    // 既存: static func diff(_:_:mode:) -> [DiffSegment]
    static func sideBySide(_ textA: String, _ textB: String) -> [DiffRow]
}
```

`sideBySide` のアルゴリズム:

1. 既存の `diff(textA, textB, mode: .line)` でユニファイドな行セグメント列を得る。
2. セグメント列を走査して `DiffRow` を構築する:
   - `.equal(line)` → `DiffRow(left: [.equal(line)], right: [.equal(line)])`
   - 連続する `.delete` 群（m 件）とその直後に続く `.insert` 群（n 件）をひとまとまりとして扱う（既存 `align` は削除→挿入→共通の順で出すため隣接する）:
     - 先頭 `min(m, n)` 組は **置換行**。各ペア (`lineL`, `lineR`) で `diff(lineL, lineR, mode: .character)` を実行し、
       - 左セル = 結果から `.equal` と `.delete` セグメントのみ（= `lineL` を文字ハイライト付きで再構成）
       - 右セル = 結果から `.equal` と `.insert` セグメントのみ（= `lineR` を文字ハイライト付きで再構成）
       - `DiffRow(left: 左セル, right: 右セル)`
     - 余った削除（m > n）→ `DiffRow(left: [.delete(line)], right: nil)`
     - 余った挿入（n > m）→ `DiffRow(left: nil, right: [.insert(line)])`

行内セルの再構成は、文字 diff のユニファイド結果から「左に見える側（equal+delete）」「右に見える側（equal+insert）」を抽出するだけ。新たな diff アルゴリズムは書かない。

### 既知の挙動・リスク

- **[MED] ペアリングが意味的に非対応な行を並べうる**: 行 diff が大きく動くと、隣接削除群と挿入群の index 対応が「内容的に対応しない行ペア」を作ることがある。古典 side-by-side でも起きる既知挙動で許容範囲。より賢い行対応（LCS ベース）は MVP には過剰。
- **[LOW] 長い行**: 折り返し（wrap）表示で横スクロールを避ける。

## ビューとコントロール

| ファイル | 変更 |
|---|---|
| `Delta/Models/DiffEngine.swift` | `DiffRow` 追加・`sideBySide(_:_:)` 追加（既存温存） |
| `Delta/Views/SplitDiffView.swift` | 新規。`[DiffRow]` と `SplitOrientation` を受け取り2ペイン描画 |
| `Delta/Views/DiffCellView.swift` | 新規。1セル `[DiffSegment]?` を描画（nil=空ギャップ、非nil=`AttributedString` で文字ハイライト） |
| `Delta/Views/DiffResultView.swift` | 削除（SplitDiffView に置換） |
| `Delta/Views/DiffWindowView.swift` | 「行/文字」Picker を「左右/上下」Picker に置換。`result: [DiffRow]`、`run()` は `sideBySide` を呼ぶ。`@AppStorage("splitOrientation")` |
| `Delta/DeltaApp.swift` / `Delta/Window/DiffWindowManager.swift` / `Delta/Views/DiffEditorView.swift` | 変更なし |

新 enum:
```swift
enum SplitOrientation: String { case horizontal; case vertical }
```

レイアウト:
- 1つの `ScrollView` に両ペインを入れて一緒にスクロールし、行揃えを維持する。
  - `horizontal`: `HStack { paneA; Divider(); paneB }`
  - `vertical`: `VStack { paneA; Divider(); paneB }`
- 各ペインはセルの `VStack`。両ペインは同一の `[DiffRow]` から作られ行数が一致するため揃う。
- セル: 等幅フォント、`maxWidth: .infinity`。行内ハイライトは文字レンジに背景色。空ギャップ行は薄いグレー。長い行は折り返し。

配色（既存踏襲）: 追加 `green.opacity(0.3)` / 削除 `red.opacity(0.3)` / 共通 無色 / ギャップ `gray.opacity(0.08)`。

## テスト・検証計画

`DiffEngine.sideBySide` を TDD で単体テスト（決定的・UI 非依存）:
- 完全一致（全行 equal、left==right）
- 純挿入（`DiffRow(left: nil, right: [.insert])` を含む）
- 純削除（`DiffRow(left: [.delete], right: nil)` を含む）
- 置換1行: `"色赤"` vs `"色青"` → 左セル `[.equal("色"), .delete("赤")]`、右セル `[.equal("色"), .insert("青")]`
- 複数行置換のペアリング
- 削除>挿入・挿入>削除の余り行
- 末尾改行差・空入力どうし

`SplitDiffView` / `DiffCellView` は UI のためビルド＋手動確認:
- 左右・上下それぞれで行揃え表示
- 変更行で日本語の行内ハイライト
- 純挿入/純削除でギャップ行が出る

## スコープ外（変更しない）

- グローバルホットキー・履歴・設定画面（次フェーズ）
- `@AppStorage("splitOrientation")` 以外の設定永続化
- スクロール同期以外の高度な UI（ミニマップ等）
- 賢い LCS ベースの行ペアリング
