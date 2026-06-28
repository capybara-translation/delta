# Delta Tab フォーカス移動 設計 (2026-06-28)

A/B 入力欄を Tab/Shift+Tab で相互に移動できるようにする。タブ文字の入力は Ctrl+Tab に割り当てる。

前提: A/B 入力欄は AppKit ラップの `CodePointTextView`（`NSTextView`）。`Delta/Views/CodePointTextView.swift`、`Delta/Views/DiffEditorView.swift`。

## 背景・動機

`NSTextView` は既定で Tab をタブ文字入力に使うため、Tab でフォーカスを移動できない。2つの入力欄を素早く行き来したいので、Tab をフォーカス移動に振り替え、タブ文字入力は Ctrl+Tab にする。

## ゴール

- A/B 入力欄で **Tab / Shift+Tab → もう一方の欄へフォーカス移動**（2ボックスのトグル）。
- **Ctrl+Tab → リテラルのタブ文字 `\t` を挿入**。
- IME 変換中（未確定文字あり）の Tab は横取りせず IME に渡す。

**成功基準**: A で Tab を押すと B にフォーカスが移り、B で Tab を押すと A に戻る。Ctrl+Tab で `\t` が入る。`TabKeyResolver` の単体テストが緑。既存テストも緑。

## 主要な設計判断

| 項目 | 決定 | 理由 |
|---|---|---|
| Tab 移動範囲 | A↔B の2ボックスのみトグル | 要望「左右を移動」に合致。Picker/実行は対象外（実行は ⌘↵）。 |
| 実装層 | AppKit（`NSTextView.keyDown` override）で完結 | `@FocusState` と NSView の同期は煩雑。厳密な A↔B 制御は AppKit が確実。 |
| タブ文字入力 | Ctrl+Tab | 通常 Tab を移動に使うための退避先。 |
| IME 保護 | `hasMarkedText()` のとき Tab を横取りしない | 日本語/ベトナム語などの変換確定を壊さない。 |
| 判定ロジック分離 | `TabKeyResolver`（純粋）に切り出す | テスト可能にし、キー判定の意図を明確化。 |
| 兄弟欄の特定 | 共有 `FocusLink`（weak 参照ホルダ） | 別々の `NSViewRepresentable` が互いの `NSTextView` を参照する手段。循環なし。 |

## コンポーネント

| ファイル | 役割 |
|---|---|
| `Delta/Models/TabKeyResolver.swift`（新規） | 純粋。キーコード＋Ctrl 有無 → `TabKeyAction`。 |
| `Delta/Views/CodePointTextView.swift`（修正） | `NSTextView` を `NavigatingTextView` サブクラスにし `keyDown` を override。`EditorField`・`FocusLink` を導入。 |
| `Delta/Views/DiffEditorView.swift`（修正） | `FocusLink` を保持し A/B に `field`・`focusLink` を渡す。 |

`DiffEngine`・`CodePointFormatter`・`DiffWindowView`・`SplitDiffView`・`DiffCellView`・`DiffWindowManager`・`DeltaApp` は無変更。

### TabKeyResolver（純粋・テスト可）

```swift
enum TabKeyAction: Equatable {
    case insertTab      // Ctrl+Tab → リテラルのタブ文字
    case focusSibling   // Tab / Shift+Tab → フォーカス移動
    case passThrough    // タブキー以外
}

enum TabKeyResolver {
    static let tabKeyCode: UInt16 = 48
    static func action(keyCode: UInt16, hasControl: Bool) -> TabKeyAction
}
```

仕様:
- `keyCode != tabKeyCode` → `.passThrough`
- `keyCode == tabKeyCode` かつ `hasControl` → `.insertTab`
- `keyCode == tabKeyCode` かつ `!hasControl` → `.focusSibling`（Shift の有無は問わない＝2欄では Tab も Shift+Tab も相手へ移動）

### CodePointTextView（修正）

- 内部 `NSTextView` を `NavigatingTextView`（`NSTextView` サブクラス）に変更。
- `NavigatingTextView` は `var onFocusSibling: (() -> Void)?` を持ち、`keyDown(with:)` を override:
  - `hasMarkedText()` が真 → `super.keyDown(with: event)`（IME に委ねる）。
  - それ以外は `TabKeyResolver.action(keyCode: event.keyCode, hasControl: event.modifierFlags.contains(.control))`:
    - `.insertTab` → `insertText("\t", replacementRange: selectedRange())`
    - `.focusSibling` → `onFocusSibling?()`
    - `.passThrough` → `super.keyDown(with: event)`
- `CodePointTextView` に `let field: EditorField`、`let focusLink: FocusLink` を追加。
- `makeNSView` で `focusLink.register(textView, as: field)` し、`textView.onFocusSibling = { focusLink.focusSibling(of: field) }` を設定。
- 既存の text 双方向同期・選択報告・スクロール配線は維持。

補助型:
```swift
enum EditorField { case a, b }

final class FocusLink {
    weak var viewA: NSView?
    weak var viewB: NSView?
    func register(_ view: NSView, as field: EditorField)
    func focusSibling(of field: EditorField)  // 相手の NSView を makeFirstResponder
}
```
`focusSibling(of:)` は相手の `NSView`（無ければ何もしない）を `target.window?.makeFirstResponder(target)` する。

### DiffEditorView（修正）

- `@State private var focusLink = FocusLink()` を保持（参照型を `@State` で安定保持）。
- A 欄: `CodePointTextView(text: $textA, field: .a, focusLink: focusLink) { ... }`、B 欄: `.b`。
- 既存のコードポイント表示・レイアウトは維持。

## リスク

- **[MED] IME 変換確定の破壊**: `hasMarkedText()` ガードで Tab を横取りしない。
- **[MED] `NSViewRepresentable` 再生成での登録切れ**: `FocusLink` を `@State` で安定保持し、`makeNSView` で登録。weak 参照のため循環なし。
- **[LOW] 兄弟がまだ window 未配置**: 両欄生成後に Tab するため `makeFirstResponder` は機能する。

## テスト・検証計画

`TabKeyResolver.action` を TDD で単体テスト:
- `action(keyCode: 48, hasControl: true)` == `.insertTab`
- `action(keyCode: 48, hasControl: false)` == `.focusSibling`
- `action(keyCode: 0, hasControl: false)` == `.passThrough`（他キー）
- `action(keyCode: 0, hasControl: true)` == `.passThrough`（Ctrl+他キー）

`NavigatingTextView`/`FocusLink`/配線は UI のためビルド＋手動確認:
- A で Tab → B にフォーカス、B で Tab → A
- Shift+Tab でも相手へ移動
- Ctrl+Tab で `\t` が入る
- IME 変換中の Tab で変換が確定し（壊れず）、フォーカス移動しない
- 既存の diff 実行・コードポイント表示が動く

## スコープ外

- 全コントロール（Picker/実行）への Tab 巡回（A↔B のみで確定）
- フォーカスリングのカスタム表示
- ホットキー・履歴・設定画面
