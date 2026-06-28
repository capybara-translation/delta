# Delta Tab フォーカス移動 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A/B 入力欄を Tab/Shift+Tab で相互移動できるようにし、タブ文字入力を Ctrl+Tab に割り当てる。

**Architecture:** キー判定は純粋関数 `TabKeyResolver`（テスト可）に分離。入力欄の `NSTextView` を `NavigatingTextView` サブクラスにして `keyDown` を override し、Tab→兄弟欄フォーカス／Ctrl+Tab→`\t`／IME 変換中は素通し。兄弟欄は共有 `FocusLink`（weak 参照）で特定。

**Tech Stack:** Swift（言語モード5）/ SwiftUI / AppKit / Swift Testing / XcodeGen。

## Global Constraints

- デプロイメントターゲット macOS 14.0 維持 / SWIFT_VERSION 5.0 / 外部 SPM 依存なし
- `DiffEngine`・`CodePointFormatter`・`DiffWindowView`・`SplitDiffView`・`DiffCellView`・`DiffWindowManager`・`DeltaApp` は無変更
- ビルド・テストは `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` を前置
- **Swift ファイルを追加したら必ず `xcodegen generate`**（.xcodeproj は project.yml から生成、gitignore 済み）
- ビルド/テストの stderr の `IDESimulatorFoundation`/`[Connection]` 警告は無害。合否は `** TEST SUCCEEDED **` / `** BUILD SUCCEEDED **` 行で判断
- Tab/Shift+Tab → A↔B トグル（2欄のみ）。Ctrl+Tab → リテラルタブ `\t`。IME 変換中（`hasMarkedText()`）の Tab は横取りしない

ビルドコマンド（参照）:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -configuration Debug -derivedDataPath build build
```
テストコマンド（参照）:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -destination 'platform=macOS' test
```

---

### Task 1: TabKeyResolver（純粋ロジック、TDD）

キーコードと Ctrl 有無から、タブ文字入力／フォーカス移動／素通しを判定する純粋関数。

**Files:**
- Create: `Delta/Models/TabKeyResolver.swift`
- Create: `DeltaTests/TabKeyResolverTests.swift`

**Interfaces:**
- Consumes: なし（Swift 標準のみ）
- Produces:
  - `enum TabKeyAction: Equatable { case insertTab; case focusSibling; case passThrough }`
  - `enum TabKeyResolver { static let tabKeyCode: UInt16; static func action(keyCode: UInt16, hasControl: Bool) -> TabKeyAction }`

- [ ] **Step 1: 失敗するテストを作成**

Create `DeltaTests/TabKeyResolverTests.swift`:
```swift
import Testing
@testable import Delta

struct TabKeyResolverTests {
    @Test func ctrlTabInsertsTab() {
        #expect(TabKeyResolver.action(keyCode: 48, hasControl: true) == .insertTab)
    }

    @Test func tabMovesFocus() {
        #expect(TabKeyResolver.action(keyCode: 48, hasControl: false) == .focusSibling)
    }

    @Test func otherKeyPassesThrough() {
        // keyCode 0 は 'a'。タブキーではない。
        #expect(TabKeyResolver.action(keyCode: 0, hasControl: false) == .passThrough)
    }

    @Test func ctrlOtherKeyPassesThrough() {
        #expect(TabKeyResolver.action(keyCode: 0, hasControl: true) == .passThrough)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

新規ファイル追加のため `xcodegen generate` が必須。

Run:
```bash
xcodegen generate && \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -destination 'platform=macOS' test 2>&1 | tail -20
```
Expected: コンパイルエラー（`cannot find 'TabKeyResolver' in scope`）でビルド失敗。

- [ ] **Step 3: TabKeyResolver を実装**

Create `Delta/Models/TabKeyResolver.swift`:
```swift
/// Tab キーに対する動作。
enum TabKeyAction: Equatable {
    case insertTab      // Ctrl+Tab → リテラルのタブ文字
    case focusSibling   // Tab / Shift+Tab → フォーカス移動
    case passThrough    // タブキー以外
}

/// キーコードと Ctrl 有無からタブキーの動作を判定する純粋ロジック。
enum TabKeyResolver {
    /// Tab キーの仮想キーコード（US 配列・物理位置で不変）。
    static let tabKeyCode: UInt16 = 48

    static func action(keyCode: UInt16, hasControl: Bool) -> TabKeyAction {
        guard keyCode == tabKeyCode else { return .passThrough }
        return hasControl ? .insertTab : .focusSibling
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run:
```bash
xcodegen generate && \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -destination 'platform=macOS' test 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`（既存35 + 新規4 = 39 全通過）

- [ ] **Step 5: コミット**

```bash
git add Delta/Models/TabKeyResolver.swift DeltaTests/TabKeyResolverTests.swift
git commit -m "feat: Tab キー動作を判定する TabKeyResolver"
```

---

### Task 2: NavigatingTextView と FocusLink で Tab フォーカス移動を配線

`NSTextView` をサブクラス化して Tab をフォーカス移動／Ctrl+Tab をタブ文字入力にし、A↔B を `FocusLink` で繋ぐ。UI のためビルド＋手動確認で検証する。

**Files:**
- Modify: `Delta/Views/CodePointTextView.swift`（全置換。`EditorField`・`FocusLink`・`NavigatingTextView` を追加し、`CodePointTextView` に `field`・`focusLink` を追加）
- Modify: `Delta/Views/DiffEditorView.swift`（全置換。`FocusLink` を保持し A/B に渡す）

**Interfaces:**
- Consumes: `TabKeyResolver.action(keyCode:hasControl:) -> TabKeyAction`、`TabKeyAction`（Task 1）、`CodePointFormatter.describe(_:)`
- Produces:
  - `enum EditorField { case a; case b }`
  - `final class FocusLink { func register(_:as:); func focusSibling(of:) }`
  - `final class NavigatingTextView: NSTextView { var onFocusSibling: (() -> Void)? }`
  - `struct CodePointTextView`（`text`・`field`・`focusLink`・`onSelectionChange`）

- [ ] **Step 1: CodePointTextView.swift を全置換**

Replace the entire contents of `Delta/Views/CodePointTextView.swift`:
```swift
import SwiftUI
import AppKit

enum EditorField {
    case a
    case b
}

/// A/B 欄が互いの NSView を見つけるための共有ホルダ。weak 参照で循環を作らない。
final class FocusLink {
    weak var viewA: NSView?
    weak var viewB: NSView?

    func register(_ view: NSView, as field: EditorField) {
        switch field {
        case .a: viewA = view
        case .b: viewB = view
        }
    }

    /// 指定欄の相手をファーストレスポンダにする。相手が無ければ何もしない。
    func focusSibling(of field: EditorField) {
        let target: NSView? = (field == .a) ? viewB : viewA
        guard let target else { return }
        target.window?.makeFirstResponder(target)
    }
}

/// Tab/Shift+Tab を兄弟欄へのフォーカス移動に、Ctrl+Tab をタブ文字入力に振り替える
/// NSTextView。IME 変換中（未確定文字あり）の Tab は横取りしない。
final class NavigatingTextView: NSTextView {
    var onFocusSibling: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if hasMarkedText() {
            super.keyDown(with: event)
            return
        }
        switch TabKeyResolver.action(
            keyCode: event.keyCode,
            hasControl: event.modifierFlags.contains(.control)
        ) {
        case .insertTab:
            insertText("\t", replacementRange: selectedRange)
        case .focusSibling:
            onFocusSibling?()
        case .passThrough:
            super.keyDown(with: event)
        }
    }
}

/// NSTextView をラップした入力欄。text を双方向同期し、選択（未選択ならカーソル直前の
/// 1書記素）を onSelectionChange で報告する。Tab で兄弟欄へフォーカス移動する。
struct CodePointTextView: NSViewRepresentable {
    @Binding var text: String
    let field: EditorField
    let focusLink: FocusLink
    var onSelectionChange: (String) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NavigatingTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.allowsUndo = true
        textView.string = text

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true

        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scroll.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )

        scroll.borderType = .bezelBorder

        focusLink.register(textView, as: field)
        textView.onFocusSibling = { [focusLink, field] in
            focusLink.focusSibling(of: field)
        }

        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // 最新のクロージャ/バインディングを Coordinator に反映する。
        context.coordinator.parent = self
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            // 注: text を外部から（ユーザー入力以外で）変更する機能を足す場合、ここでの
            // string 代入が選択変更通知を同期発火し report() → @State 書き込みが
            // ビュー更新中に走り得る。その際は report() を再入ガード/遅延する。
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodePointTextView
        init(_ parent: CodePointTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            report(textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            report(textView)
        }

        /// 選択テキスト（未選択ならカーソル直前の1書記素）を報告する。
        private func report(_ textView: NSTextView) {
            let ns = textView.string as NSString
            let range = textView.selectedRange
            let selected: String
            if range.length > 0, NSMaxRange(range) <= ns.length {
                selected = ns.substring(with: range)
            } else if range.location > 0, range.location <= ns.length {
                let composed = ns.rangeOfComposedCharacterSequence(at: range.location - 1)
                selected = ns.substring(with: composed)
            } else {
                selected = ""
            }
            parent.onSelectionChange(selected)
        }
    }
}
```

- [ ] **Step 2: DiffEditorView.swift を全置換**

Replace the entire contents of `Delta/Views/DiffEditorView.swift`:
```swift
import SwiftUI

struct DiffEditorView: View {
    @Binding var textA: String
    @Binding var textB: String
    @State private var infoA: String = ""
    @State private var infoB: String = ""
    @State private var focusLink = FocusLink()

    var body: some View {
        HStack(spacing: 8) {
            editor("A", field: .a, text: $textA, info: $infoA)
            editor("B", field: .b, text: $textB, info: $infoB)
        }
    }

    private func editor(_ label: String, field: EditorField, text: Binding<String>, info: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            CodePointTextView(text: text, field: field, focusLink: focusLink) { selected in
                info.wrappedValue = CodePointFormatter.describe(selected)
            }

            Text(info.wrappedValue.isEmpty ? " " : info.wrappedValue)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }
}
```

- [ ] **Step 3: ビルド**

ファイルの追加・削除はない（既存2ファイルの全置換のみ）ので `xcodegen generate` は不要。

Run:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -configuration Debug -derivedDataPath build build 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: テストが引き続き通ることを確認**

Run:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -destination 'platform=macOS' test 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`（39 全通過）

- [ ] **Step 5: 手動で動作確認**

新バイナリで確認するため、起動中の旧プロセスを止めてから開く:
```bash
pkill -x Delta; sleep 1
open build/Build/Products/Debug/Delta.app
```
確認手順（目視）:
1. メニューバー δ →「Open Diff Window」
2. A にカーソルを置き Tab → B にフォーカスが移る。B で Tab → A に戻る
3. Shift+Tab でも相手の欄へ移る
4. Ctrl+Tab を押すと現在の欄に `\t`（タブ文字）が入る
5. 日本語/ベトナム語を IME で入力中（未確定の下線がある状態）に Tab → 変換が確定し（壊れず）、フォーカスは移動しない
6. 既存のコードポイント表示・実行（⌘↵）・side-by-side が引き続き動く

- [ ] **Step 6: コミット**

```bash
git add Delta/Views/CodePointTextView.swift Delta/Views/DiffEditorView.swift
git commit -m "feat: Tab で A/B 欄を移動、Ctrl+Tab でタブ文字入力"
```

---

## 完了の定義

- `TabKeyResolver` の単体テスト4件＋既存35件が緑（計39、`** TEST SUCCEEDED **`）
- `xcodebuild build` 成功
- 手動確認（Task 2 Step 5）で Tab/Shift+Tab のフォーカス移動・Ctrl+Tab のタブ入力・IME 変換中の素通しが確認できる
- デプロイメントターゲット macOS 14・diff 機能・公開 API は無変更
