# Delta 選択文字のコードポイント表示 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A/B 入力欄で選択中（未選択ならカーソル直前1書記素）の文字の Unicode コードポイントを各欄の下に表示する。

**Architecture:** 表示文字列生成は純粋関数 `CodePointFormatter`（テスト可）に分離。入力欄は AppKit `NSTextView` を `NSViewRepresentable`（`CodePointTextView`）でラップして選択を取得。`DiffEditorView` が両者を繋ぎ各欄の下に表示する。diff 機能・公開 API は無変更。

**Tech Stack:** Swift（言語モード5）/ SwiftUI / AppKit / Swift Testing / XcodeGen。

## Global Constraints

- デプロイメントターゲットは macOS 14.0 を**維持**（変更しない）。SWIFT_VERSION 5.0 / 外部 SPM 依存なし
- `DiffEngine`・`DiffWindowView`・`SplitDiffView`・`DiffCellView`・`DiffWindowManager`・`DeltaApp` は無変更
- ビルド・テストは `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` を前置
- **Swift ファイルを追加したら必ず `xcodegen generate` を実行**してからビルド（.xcodeproj は project.yml から生成、gitignore 済み）
- ビルド/テストの stderr の `IDESimulatorFoundation`/`[Connection]` 警告は無害。合否は `** TEST SUCCEEDED **` / `** BUILD SUCCEEDED **` 行で判断
- 表記: 各スカラー `U+XXXX`（最小4桁）。ちょうど1スカラーのとき `Unicode.Scalar.Properties.name` を併記。複数は空白連結。24個超は先頭24＋` … (+N)`

ビルドコマンド（参照）:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -configuration Debug -derivedDataPath build build
```
テストコマンド（参照）:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -destination 'platform=macOS' test
```

---

### Task 1: CodePointFormatter（純粋ロジック、TDD）

選択文字列を `U+XXXX ...` の表示文字列に変換する純粋関数。UI 非依存でテストする。

**Files:**
- Create: `Delta/Models/CodePointFormatter.swift`
- Create: `DeltaTests/CodePointFormatterTests.swift`

**Interfaces:**
- Consumes: なし（Swift 標準のみ）
- Produces: `enum CodePointFormatter { static let maxScalars: Int; static func describe(_ text: String) -> String }`

- [ ] **Step 1: 失敗するテストを作成**

Create `DeltaTests/CodePointFormatterTests.swift`:
```swift
import Testing
@testable import Delta

struct CodePointFormatterTests {
    @Test func emptyIsEmpty() {
        #expect(CodePointFormatter.describe("") == "")
    }

    @Test func singleAsciiHasName() {
        #expect(CodePointFormatter.describe("A") == "U+0041 LATIN CAPITAL LETTER A")
    }

    @Test func singleNFCVietnameseHasName() {
        // NFC「ờ」= U+1EDD（1スカラー）→ 名前併記
        #expect(CodePointFormatter.describe("\u{1EDD}") == "U+1EDD LATIN SMALL LETTER O WITH HORN AND GRAVE")
    }

    @Test func nfdVietnameseListsScalars() {
        // NFD「ờ」= o + 結合ホーン + 結合グレーブ（3スカラー）→ 名前なし
        #expect(CodePointFormatter.describe("\u{006F}\u{031B}\u{0300}") == "U+006F U+031B U+0300")
    }

    @Test func multipleCharactersListScalars() {
        #expect(CodePointFormatter.describe("AB") == "U+0041 U+0042")
    }

    @Test func capsLongSelection() {
        let r = CodePointFormatter.describe(String(repeating: "a", count: 25))
        let expected = Array(repeating: "U+0061", count: 24).joined(separator: " ") + " … (+1)"
        #expect(r == expected)
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
Expected: コンパイルエラー（`cannot find 'CodePointFormatter' in scope`）でビルド失敗。

- [ ] **Step 3: CodePointFormatter を実装**

Create `Delta/Models/CodePointFormatter.swift`:
```swift
/// 選択文字列を「U+XXXX ...」の表示文字列にする純粋関数。
enum CodePointFormatter {
    static let maxScalars = 24

    /// 各スカラーを U+XXXX で列挙する。ちょうど1スカラーのときは Unicode 名を併記。
    /// 空入力は空文字。maxScalars を超える場合は先頭 maxScalars 個＋" … (+N)"。
    static func describe(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        if scalars.isEmpty { return "" }

        var parts = scalars.prefix(maxScalars).map(hex)
        if scalars.count == 1, let name = scalars.first?.properties.name, !name.isEmpty {
            parts[0] += " " + name
        }

        var result = parts.joined(separator: " ")
        if scalars.count > maxScalars {
            result += " … (+\(scalars.count - maxScalars))"
        }
        return result
    }

    /// スカラーを最小4桁の "U+XXXX"（大文字16進）にする。
    private static func hex(_ scalar: Unicode.Scalar) -> String {
        let digits = String(scalar.value, radix: 16, uppercase: true)
        let padded = digits.count < 4
            ? String(repeating: "0", count: 4 - digits.count) + digits
            : digits
        return "U+" + padded
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run:
```bash
xcodegen generate && \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -destination 'platform=macOS' test 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`（既存26 + 新規6 = 32 全通過）

- [ ] **Step 5: コミット**

```bash
git add Delta/Models/CodePointFormatter.swift DeltaTests/CodePointFormatterTests.swift
git commit -m "feat: 選択文字のコードポイント表示文字列を生成する CodePointFormatter"
```

---

### Task 2: CodePointTextView と DiffEditorView 配線（AppKit ラップ）

`NSTextView` ラップで選択を取得し、各欄の下にコードポイントを表示する。UI のためビルド＋手動確認で検証する。

**Files:**
- Create: `Delta/Views/CodePointTextView.swift`
- Modify: `Delta/Views/DiffEditorView.swift`（全置換）

**Interfaces:**
- Consumes: `CodePointFormatter.describe(_:) -> String`（Task 1）
- Produces:
  - `struct CodePointTextView: NSViewRepresentable { @Binding var text: String; var onSelectionChange: (String) -> Void }`

- [ ] **Step 1: CodePointTextView を作成**

Create `Delta/Views/CodePointTextView.swift`:
```swift
import SwiftUI
import AppKit

/// NSTextView をラップした入力欄。text を双方向同期し、選択（未選択ならカーソル直前の
/// 1書記素）を onSelectionChange で報告する。macOS 14 の TextEditor が選択 API を
/// 持たないための AppKit ラップ。
struct CodePointTextView: NSViewRepresentable {
    @Binding var text: String
    var onSelectionChange: (String) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
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
        scroll.borderType = .bezelBorder
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // 最新のクロージャ/バインディングを Coordinator に反映する。
        context.coordinator.parent = self
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
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
            let range = textView.selectedRange()
            let selected: String
            if range.length > 0 {
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

- [ ] **Step 2: DiffEditorView を差し替え**

Replace the entire contents of `Delta/Views/DiffEditorView.swift`:
```swift
import SwiftUI

struct DiffEditorView: View {
    @Binding var textA: String
    @Binding var textB: String
    @State private var infoA: String = ""
    @State private var infoB: String = ""

    var body: some View {
        HStack(spacing: 8) {
            editor("A", text: $textA, info: $infoA)
            editor("B", text: $textB, info: $infoB)
        }
    }

    private func editor(_ label: String, text: Binding<String>, info: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            CodePointTextView(text: text) { selected in
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

- [ ] **Step 3: プロジェクト再生成してビルド**

新規ファイル追加のため `xcodegen generate` が必須。

Run:
```bash
xcodegen generate && \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -configuration Debug -derivedDataPath build build 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: テストが引き続き通ることを確認**

Run:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -destination 'platform=macOS' test 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`（32 全通過）

- [ ] **Step 5: 手動で動作確認**

Run:
```bash
open build/Build/Products/Debug/Delta.app
```
確認手順（目視）:
1. メニューバー δ →「Open Diff Window」
2. A に `Đường`（NFC）を入力し「ờ」を選択 → A 欄の下に `U+1EDD LATIN SMALL LETTER O WITH HORN AND GRAVE`
3. B に NFD の `Đường` を入力し「ờ」を選択 → B 欄の下に `U+006F U+031B U+0300`（複数スカラー）
4. 選択を外しカーソルを文字の直後に置く → 直前1文字のスカラーが出る
5. 入力・カーソル移動でカーソルが飛ばない（同期ループなし）
6. 実行（⌘↵）で side-by-side 表示が引き続き動く

- [ ] **Step 6: コミット**

```bash
git add Delta/Views/CodePointTextView.swift Delta/Views/DiffEditorView.swift
git commit -m "feat: 入力欄を AppKit ラップにし選択文字のコードポイントを表示"
```

---

## 完了の定義

- `CodePointFormatter` の単体テスト6件＋既存26件が緑（計32、`** TEST SUCCEEDED **`）
- `xcodebuild build` 成功
- 手動確認（Task 2 Step 5）で A/B 各欄の下に選択文字のコードポイントが出る／NFC・NFD の違いが見える／カーソルが飛ばない
- デプロイメントターゲット macOS 14・diff 機能・公開 API は無変更
