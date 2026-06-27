# Delta スカラー敏感 diff 設計 (2026-06-27)

Delta の diff 比較を Unicode の正準等価から「Unicode スカラー列の一致」へ変更し、NFC/NFD など符号化（エンコード）の違いを常に差分として検出できるようにする。

前提: side-by-side 表示と `DiffEngine`（`diff(_:_:mode:)` / `sideBySide(_:_:)`）が `main` に実装済み。

## 背景・動機

見た目が同じでも符号化が異なる文字（例: ベトナム語「ờ」の NFC=`U+1EDD` と NFD=`U+006F U+031B U+0300`）を、Delta は差分として表示しない。

原因は **Swift の `String`/`Character` の `==` が Unicode 正準等価で判定する**こと。`DiffEngine` の `tokenize` は書記素クラスタ（`Character`）でトークン化し、`CollectionDifference` が `String` の `==`（正準等価）で比較するため、正準等価な符号化違いは「同じ」とみなされる。さらに side-by-side はまず行単位で比較するため、符号化だけ異なる行は「同じ行」とされ、変更行として検出されず文字 diff にも到達しない。

このツールの目的はこうした文字レベルの差分検出なので、比較基盤を符号化に敏感な方式へ変更する。

## ゴール

diff の一致判定を **Unicode スカラー列の一致**で行い、NFC/NFD など符号化違いを常に差分として検出する。

**成功基準**: NFC の「ờ」と NFD の「ờ」を含む入力が差分として表示され、`DiffEngine` の新規テストが緑。既存23テストも緑（リグレッションなし）。

## 主要な設計判断

| 項目 | 決定 | 理由 |
|---|---|---|
| 有効範囲 | **常にスカラー比較**（トグルなし） | 符号化違いの検出がツールの目的。UI を増やさない。 |
| 適用レベル | **行・文字の両方** | 両者とも同じ `tokenize`/`align` を通る。片方だけでは行比較が符号化違いを潰し文字 diff に到達しない。 |
| ハイライト粒度 | 書記素クラスタ（見た目の1文字）単位 | トークン化は書記素単位のまま。表示が崩れない（単独の結合文字を出さない）。 |
| 比較基盤 | スカラー列で `==`/`hash` するトークン型を導入 | `CollectionDifference` の差分判定を符号化敏感にする最小変更。`DiffSegment` は `String` のままで UI 無変更。 |

## 実装（`Delta/Models/DiffEngine.swift` のみ）

正準等価ではなく Unicode スカラー列で同一性を判定するトークン型を導入する:

```swift
/// 正準等価ではなく Unicode スカラー列で一致を判定するトークン。
/// String/Character の == は正準等価のため NFC/NFD 等を区別できない。
/// diff の検出はこのトークンの == / hash（スカラー基準）で行う。
private struct ExactToken: Hashable {
    let text: String
    static func == (lhs: ExactToken, rhs: ExactToken) -> Bool {
        lhs.text.unicodeScalars.elementsEqual(rhs.text.unicodeScalars)
    }
    func hash(into hasher: inout Hasher) {
        for scalar in text.unicodeScalars { hasher.combine(scalar.value) }
    }
}
```

変更点:
- `tokenize(_:mode:)` の戻り値を `[String]` → `[ExactToken]` に変更。トークン化規則は据え置き（line=`split(separator:"\n", omittingEmptySubsequences:false)`、character=`map(String.init)` で書記素単位）。各トークンは `ExactToken(text: String(...))`。
- `align(_:_:)` の引数を `[ExactToken]` に変更。`CollectionDifference` は `ExactToken` の `==`/`hash`（スカラー基準）で差分を取る。`DiffSegment` はこれまで通り `token.text` から組む。
- `tokenize`/`align` は内部実装の詳細であり、`ExactToken` を露出させないため必要に応じて `private` に下げる（外部・テストは `diff`/`sideBySide` のみ使用）。
- `diff(_:_:mode:)` と `sideBySide(_:_:)` の公開シグネチャは不変。`sideBySide` は内部で `diff` を呼ぶため自動的に符号化敏感になる（行ペア検出も行内ハイライトも）。

`DiffMode`/`DiffKind`/`DiffSegment` および View 層は無変更。

## 互換性・リスク

- **[互換] 既存23テストは不変で緑**: ASCII/日本語の「同一 or 明確に別」の比較のみで、スカラー比較でも判定結果は変わらない。
- **[LOW] 単独の結合文字**: 書記素単位トークン化を維持するため、表示は「見た目の1文字」全体に色が付く。単独の結合文字を切り出して表示することはない。
- **[注意] NFC↔NFD は複数文字に及ぶことがある**: 例 `Đường` を NFC↔NFD 変換すると「ư」「ờ」の双方が分解され2文字差になる。実装は実際のスカラー差をそのまま検出する。テストは誤解を避けるため1文字だけ符号化が異なる制御済み入力を用いる。

## テスト・検証計画（TDD、`DiffEngineTests` に追加）

- `diff("\u{1EDD}", "\u{006F}\u{031B}\u{0300}", mode: .character)`（NFC ờ vs NFD ờ）→ `[DiffSegment(.delete, "\u{1EDD}"), DiffSegment(.insert, "\u{006F}\u{031B}\u{0300}")]`
- `sideBySide("A\u{1EDD}B", "A\u{006F}\u{031B}\u{0300}B")` → 1行の置換で、左 `[equal "A", delete "\u{1EDD}", equal "B"]` / 右 `[equal "A", insert "\u{006F}\u{031B}\u{0300}", equal "B"]`
- リグレッション: `diff("a", "a", mode: .character)` は差分なし（完全一致）。既存テスト群で「別文字は差分あり」を担保。

UI 変更はないため自動テスト中心。手動確認として、実際の NFC/NFD 入力で side-by-side に行内ハイライトが出ることを目視する。

## スコープ外

- 比較方式のトグル UI（常時スカラー比較で確定）
- スカラー単位ハイライト（書記素単位で確定）
- 入力の正規化機能（NFC 統一など。むしろ符号化差を消すので不採用）
- ホットキー・履歴・設定画面（別フェーズ）
