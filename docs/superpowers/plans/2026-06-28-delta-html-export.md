# Delta Diff HTML エクスポート Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ツールバーの Export ボタンから、現在の比較結果を「現在の表示向きに追従した自己完結 HTML」として保存する。

**Architecture:** HTML 生成は純粋関数 `HTMLExporter`（`rows`＋`orientation`＋`generatedAt` → HTML 文字列）として TDD。`DiffWindowView` に Export ボタン＋`NSSavePanel`＋ファイル書き出しを配線。

**Tech Stack:** Swift（言語モード5）/ SwiftUI / AppKit / UniformTypeIdentifiers / Swift Testing / XcodeGen。

## Global Constraints

- デプロイメントターゲット macOS 14.0 維持 / SWIFT_VERSION 5.0 / 外部 SPM 依存なし
- `DiffEngine`・`SplitDiffView`・`DiffCellView`・`CodePointTextView`・`HistoryStore`・`HistoryView`・`SettingsView`・`DiffWindowManager`・`GlobalHotKey` は無変更
- ビルド・テストは `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` を前置
- **Swift ファイルを追加したら必ず `xcodegen generate`**（.xcodeproj は project.yml から生成、gitignore 済み）
- ビルド/テストの stderr の `IDESimulatorFoundation`/`[Connection]` 警告は無害。合否は `** BUILD SUCCEEDED **` / `** TEST SUCCEEDED **` 行で判断
- HTML は自己完結（CSS インライン・外部依存なし）。配色: 追加 `#ccffd8` / 削除 `#ffd7d5` / ギャップ `#f0f0f0`。すべての可視テキストを HTML エスケープ。向きは引数の `orientation` に追従

ビルドコマンド（参照）:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -configuration Debug -derivedDataPath build build
```
テストコマンド（参照）:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -destination 'platform=macOS' test
```

---

### Task 1: HTMLExporter（純粋ロジック、TDD）

`rows`・`orientation`・`generatedAt` から自己完結 HTML を生成する純粋関数を TDD で実装する。

**Files:**
- Create: `Delta/Models/HTMLExporter.swift`
- Create: `DeltaTests/HTMLExporterTests.swift`

**Interfaces:**
- Consumes: `DiffRow`、`DiffSegment`、`DiffKind`、`SplitOrientation`、`DiffEngine.sideBySide`（テスト用）
- Produces: `enum HTMLExporter { static func html(rows: [DiffRow], orientation: SplitOrientation, generatedAt: Date) -> String }`

- [ ] **Step 1: 失敗するテストを作成**

Create `DeltaTests/HTMLExporterTests.swift`:
```swift
import Testing
import Foundation
@testable import Delta

struct HTMLExporterTests {
    private let epoch = Date(timeIntervalSince1970: 0)

    @Test func producesSelfContainedDocument() {
        let rows = DiffEngine.sideBySide("a", "b")
        let html = HTMLExporter.html(rows: rows, orientation: .horizontal, generatedAt: epoch)
        #expect(html.contains("<!DOCTYPE html>"))
        #expect(html.contains("<style>"))
    }

    @Test func headerContainsGeneratedDate() {
        let html = HTMLExporter.html(rows: [], orientation: .horizontal, generatedAt: epoch)
        #expect(html.contains("1970-01-01T00:00:00Z"))
    }

    @Test func escapesHTMLSpecialChars() {
        // char diff of "<x>" vs "&y": left deletes <,x,> ; right inserts &,y
        let rows = DiffEngine.sideBySide("<x>", "&y")
        let html = HTMLExporter.html(rows: rows, orientation: .horizontal, generatedAt: epoch)
        #expect(html.contains("&lt;"))
        #expect(html.contains("&gt;"))
        #expect(html.contains("&amp;"))
        #expect(!html.contains("<x>"))
    }

    @Test func horizontalProducesTableWithRowPerDiffRow() {
        let rows = DiffEngine.sideBySide("a\nb", "a\nc")
        let html = HTMLExporter.html(rows: rows, orientation: .horizontal, generatedAt: epoch)
        #expect(html.contains("<table"))
        let trCount = html.components(separatedBy: "<tr>").count - 1
        #expect(trCount == rows.count)
    }

    @Test func verticalProducesTwoPanes() {
        let rows = DiffEngine.sideBySide("a\nb", "a\nc")
        let html = HTMLExporter.html(rows: rows, orientation: .vertical, generatedAt: epoch)
        #expect(html.contains("diff v"))
        let paneCount = html.components(separatedBy: "class=\"pane\"").count - 1
        #expect(paneCount == 2)
    }

    @Test func intralineChangeUsesSpans() {
        // "abc" vs "abd": equal a,b ; delete c / insert d
        let rows = DiffEngine.sideBySide("abc", "abd")
        let html = HTMLExporter.html(rows: rows, orientation: .horizontal, generatedAt: epoch)
        #expect(html.contains("<span class=\"del\">c</span>"))
        #expect(html.contains("<span class=\"ins\">d</span>"))
    }

    @Test func wholeLineAndGap() {
        // "a\nb" vs "a": equal a row, then delete "b" (left whole-line delete, right gap)
        let rows = DiffEngine.sideBySide("a\nb", "a")
        let html = HTMLExporter.html(rows: rows, orientation: .horizontal, generatedAt: epoch)
        #expect(html.contains("class=\"del\""))
        #expect(html.contains("class=\"gap\""))
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

新規ファイル追加のため `xcodegen generate` が必須。

Run:
```bash
xcodegen generate && \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -destination 'platform=macOS' test 2>&1 | tail -25
```
Expected: コンパイルエラー（`cannot find 'HTMLExporter' in scope`）でビルド失敗。

- [ ] **Step 3: HTMLExporter を実装**

Create `Delta/Models/HTMLExporter.swift`:
```swift
import Foundation

/// Generates a self-contained HTML document for a diff result, following the given orientation.
enum HTMLExporter {
    static func html(rows: [DiffRow], orientation: SplitOrientation, generatedAt: Date) -> String {
        let body: String
        switch orientation {
        case .horizontal:
            let trs = rows.map { "<tr>\(cell($0.left))\(cell($0.right))</tr>" }.joined(separator: "\n")
            body = "<table class=\"diff h\">\n\(trs)\n</table>"
        case .vertical:
            let left = rows.map { lineDiv($0.left) }.joined(separator: "\n")
            let right = rows.map { lineDiv($0.right) }.joined(separator: "\n")
            body = "<div class=\"diff v\">\n<div class=\"pane\">\n\(left)\n</div>\n<div class=\"pane\">\n\(right)\n</div>\n</div>"
        }

        let meta = "Generated: " + ISO8601DateFormatter().string(from: generatedAt)

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <title>Delta Diff</title>
        <style>
        body { font-family: ui-monospace, Menlo, monospace; margin: 16px; }
        .meta { color: #666; font-size: 12px; margin-bottom: 12px; }
        table.diff { border-collapse: collapse; width: 100%; }
        table.diff td { vertical-align: top; width: 50%; padding: 0 6px; border-left: 1px solid #ddd; white-space: pre; }
        .pane { border-bottom: 1px solid #ddd; padding: 6px 0; }
        .line { white-space: pre; }
        .ins { background: #ccffd8; }
        .del { background: #ffd7d5; }
        .gap { background: #f0f0f0; }
        </style>
        </head>
        <body>
        <p class="meta">\(escape(meta))</p>
        \(body)
        </body>
        </html>
        """
    }

    /// Table cell (horizontal). nil = gap.
    private static func cell(_ segments: [DiffSegment]?) -> String {
        guard let segments else { return "<td class=\"gap\">\(nbsp)</td>" }
        let (cls, inner) = render(segments)
        let classAttr = cls.isEmpty ? "" : " class=\"\(cls)\""
        return "<td\(classAttr)>\(inner)</td>"
    }

    /// Line in a vertical pane. nil = gap.
    private static func lineDiv(_ segments: [DiffSegment]?) -> String {
        guard let segments else { return "<div class=\"line gap\">\(nbsp)</div>" }
        let (cls, inner) = render(segments)
        let classAttr = cls.isEmpty ? "line" : "line \(cls)"
        return "<div class=\"\(classAttr)\">\(inner)</div>"
    }

    /// Returns (whole-line background class, inner HTML).
    /// A single non-equal segment colors the whole cell; otherwise changed runs are wrapped in spans.
    private static func render(_ segments: [DiffSegment]) -> (String, String) {
        let joined = segments.map(\.text).joined()
        if joined.isEmpty { return ("", nbsp) }
        if segments.count == 1, segments[0].kind != .equal {
            return (segments[0].kind == .insert ? "ins" : "del", escape(joined))
        }
        let inner = segments.map { seg -> String in
            let t = escape(seg.text)
            switch seg.kind {
            case .equal: return t
            case .insert: return "<span class=\"ins\">\(t)</span>"
            case .delete: return "<span class=\"del\">\(t)</span>"
            }
        }.joined()
        return ("", inner)
    }

    private static let nbsp = "&nbsp;"

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run:
```bash
xcodegen generate && \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -destination 'platform=macOS' test 2>&1 | tail -25
```
Expected: `** TEST SUCCEEDED **`（既存48 + 新規7 = 55 全通過）

- [ ] **Step 5: コミット**

```bash
git add Delta/Models/HTMLExporter.swift DeltaTests/HTMLExporterTests.swift
git commit -m "feat: 比較結果を HTML 化する HTMLExporter（純粋）"
```

---

### Task 2: Export ボタンと保存配線

`DiffWindowView` に Export ボタンと `NSSavePanel` 経由のファイル書き出しを追加する。UI のためビルド＋手動確認で検証する。

**Files:**
- Modify: `Delta/Views/DiffWindowView.swift`（全置換）

**Interfaces:**
- Consumes: `HTMLExporter.html(rows:orientation:generatedAt:)`（Task 1）

- [ ] **Step 1: DiffWindowView を全置換**

Replace the entire contents of `Delta/Views/DiffWindowView.swift`:
```swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DiffWindowView: View {
    @AppStorage("textA") private var textA = ""
    @AppStorage("textB") private var textB = ""
    @AppStorage("splitOrientation") private var orientation: SplitOrientation = .horizontal
    @State private var rows: [DiffRow] = []
    @State private var history = HistoryStore()
    @State private var showingHistory = false

    var body: some View {
        VStack(spacing: 8) {
            DiffEditorView(textA: $textA, textB: $textB)
                .frame(minHeight: 160)

            HStack {
                Picker("", selection: $orientation) {
                    Text("Horizontal").tag(SplitOrientation.horizontal)
                    Text("Vertical").tag(SplitOrientation.vertical)
                }
                .pickerStyle(.segmented)
                .fixedSize()

                Spacer()

                Button("History") { showingHistory.toggle() }
                    .popover(isPresented: $showingHistory, arrowEdge: .bottom) {
                        HistoryView(store: history) { entry in
                            textA = entry.textA
                            textB = entry.textB
                            showingHistory = false
                        }
                    }

                Button("Export") { export() }
                    .disabled(rows.isEmpty)

                Button("Compare") { run() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
            }

            Divider()

            SplitDiffView(rows: rows, orientation: orientation)
        }
        .padding(12)
        .frame(minWidth: 480, minHeight: 420)
    }

    private func run() {
        rows = DiffEngine.sideBySide(textA, textB)
        history.add(textA: textA, textB: textB, date: Date())
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = "delta-diff.html"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let html = HTMLExporter.html(rows: rows, orientation: orientation, generatedAt: Date())
        try? html.write(to: url, atomically: true, encoding: .utf8)
    }
}
```

- [ ] **Step 2: ビルド**

ファイルの追加・削除はない（既存1ファイルの全置換のみ）ので `xcodegen generate` は不要。

Run:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -configuration Debug -derivedDataPath build build 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: テストが引き続き通ることを確認**

Run:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -destination 'platform=macOS' test 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`（55 全通過）

- [ ] **Step 4: 起動して手動確認**

新バイナリで確認するため旧プロセスを止めてから開く:
```bash
pkill -x Delta; sleep 1
open build/Build/Products/Debug/Delta.app && sleep 2 && pgrep -x Delta
```
プロセスが生きていること（即クラッシュしないこと）を確認。実装者はここまで（プロセス生存）を報告する。以降はコントローラ/ユーザーが確認する:
1. A/B に入力し Compare → Export ボタンが有効になる（結果なしのときは無効）
2. Export → 保存ダイアログ → 保存した `.html` をブラウザで開くと、アプリと同じ色付き diff
3. Vertical 表示のときは HTML も上下、Horizontal のときは左右
4. 既存の diff・履歴・設定・Tab・⌃⌥D が引き続き動く

- [ ] **Step 5: コミット**

```bash
git add Delta/Views/DiffWindowView.swift
git commit -m "feat: Export ボタンで比較結果を HTML 保存"
```

---

## 完了の定義

- `HTMLExporter` の単体テスト7件＋既存48件が緑（計55、`** TEST SUCCEEDED **`）
- `xcodebuild build` 成功
- 手動確認（Task 2 Step 4）で Export → HTML 保存 → ブラウザで色付き diff（向き一致）が確認できる
- デプロイメントターゲット macOS 14・既存機能・diff ロジックは無変更
