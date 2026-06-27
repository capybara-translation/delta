# Delta Side-by-Side 差分表示 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 結果表示をユニファイド1列から、左右2ペインの行揃え side-by-side（変更行は文字単位ハイライト、左右/上下の分割向きを切替・永続化）に変更する。

**Architecture:** `DiffEngine` に純粋関数 `sideBySide` を追加し、既存の行 diff と文字 diff を再利用して「行揃えの行ペア」`[DiffRow]` を生成する（新アルゴリズムは書かない）。View 層は `SplitDiffView` + `DiffCellView` に置換し、向きは `SplitOrientation` で切替。既存の `diff(_:_:mode:)` と DiffEngine の全テストは温存する。

**Tech Stack:** Swift（言語モード5）/ SwiftUI / Swift Testing / XcodeGen / 外部 SPM 依存なし。

## Global Constraints

- 既存 `main` の実装（`DiffEngine`・各 View）を土台にする。`DiffMode`/`DiffKind`/`DiffSegment`/`diff(_:_:mode:)` と既存テストは**変更しない**
- デプロイメントターゲット macOS 14.0 / `SWIFT_VERSION = 5.0` / 外部 SPM 依存なし
- ビルド・テストは必ず `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` を前置
- `.xcodeproj` は `project.yml` から生成（gitignore 済み）。**Swift ファイルを追加・削除したら必ず `xcodegen generate` を実行**してからビルド
- ビルド/テストの stderr に出る `IDESimulatorFoundation` / `[Connection]` 警告は無害。合否は `** BUILD SUCCEEDED **` / `** TEST SUCCEEDED **` の行で判断
- 文字単位は書記素クラスタ（Swift `Character`）。空白 split は禁止
- 配色: 追加 `green.opacity(0.3)` / 削除 `red.opacity(0.3)` / 共通 無色 / ギャップ `gray.opacity(0.08)`
- 行揃え（ギャップ補完）、変更行ペア内は行内文字ハイライト。「行/文字」トグルは撤去し「左右/上下」トグルに置換。向きは `@AppStorage("splitOrientation")` で永続化

ビルドコマンド（参照）:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -configuration Debug -derivedDataPath build build
```
テストコマンド（参照）:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -destination 'platform=macOS' test
```

---

### Task 1: DiffEngine に DiffRow と sideBySide を追加（TDD）

行揃えの行ペア列を生成する純粋関数を追加する。既存の行 diff と文字 diff を再利用する。既存 API・テストは触らない。

**Files:**
- Modify: `Delta/Models/DiffEngine.swift`（末尾に `DiffRow` と `sideBySide`/`pairRows` を追加）
- Modify: `DeltaTests/DiffEngineTests.swift`（`struct DiffEngineTests` 内に side-by-side テストを追加）

**Interfaces:**
- Consumes（既存）: `DiffEngine.diff(_:_:mode:) -> [DiffSegment]`、`DiffSegment`、`DiffKind`
- Produces:
  - `struct DiffRow: Equatable { let left: [DiffSegment]?; let right: [DiffSegment]? }`
  - `static func DiffEngine.sideBySide(_ textA: String, _ textB: String) -> [DiffRow]`

- [ ] **Step 1: 失敗するテストを追加**

`DeltaTests/DiffEngineTests.swift` の `struct DiffEngineTests { ... }` の閉じ括弧の直前に以下を追加:
```swift
    // MARK: - sideBySide

    @Test func sideBySideAllEqual() {
        let r = DiffEngine.sideBySide("a\nb", "a\nb")
        #expect(r == [
            DiffRow(left: [DiffSegment(kind: .equal, text: "a")], right: [DiffSegment(kind: .equal, text: "a")]),
            DiffRow(left: [DiffSegment(kind: .equal, text: "b")], right: [DiffSegment(kind: .equal, text: "b")]),
        ])
    }

    @Test func sideBySidePureInsert() {
        let r = DiffEngine.sideBySide("a", "a\nb")
        #expect(r == [
            DiffRow(left: [DiffSegment(kind: .equal, text: "a")], right: [DiffSegment(kind: .equal, text: "a")]),
            DiffRow(left: nil, right: [DiffSegment(kind: .insert, text: "b")]),
        ])
    }

    @Test func sideBySidePureDelete() {
        let r = DiffEngine.sideBySide("a\nb", "a")
        #expect(r == [
            DiffRow(left: [DiffSegment(kind: .equal, text: "a")], right: [DiffSegment(kind: .equal, text: "a")]),
            DiffRow(left: [DiffSegment(kind: .delete, text: "b")], right: nil),
        ])
    }

    @Test func sideBySideIntralineReplace() {
        let r = DiffEngine.sideBySide("色赤", "色青")
        #expect(r == [
            DiffRow(
                left: [DiffSegment(kind: .equal, text: "色"), DiffSegment(kind: .delete, text: "赤")],
                right: [DiffSegment(kind: .equal, text: "色"), DiffSegment(kind: .insert, text: "青")]
            ),
        ])
    }

    @Test func sideBySideMultiLineReplacePairing() {
        let r = DiffEngine.sideBySide("a\nb\nc", "x\ny\nc")
        #expect(r == [
            DiffRow(left: [DiffSegment(kind: .delete, text: "a")], right: [DiffSegment(kind: .insert, text: "x")]),
            DiffRow(left: [DiffSegment(kind: .delete, text: "b")], right: [DiffSegment(kind: .insert, text: "y")]),
            DiffRow(left: [DiffSegment(kind: .equal, text: "c")], right: [DiffSegment(kind: .equal, text: "c")]),
        ])
    }

    @Test func sideBySideMoreDeletesThanInserts() {
        // A=["a","b","c"], B=["x"]; 行 diff: [del a, del b, del c, ins x]
        let r = DiffEngine.sideBySide("a\nb\nc", "x")
        #expect(r == [
            DiffRow(left: [DiffSegment(kind: .delete, text: "a")], right: [DiffSegment(kind: .insert, text: "x")]),
            DiffRow(left: [DiffSegment(kind: .delete, text: "b")], right: nil),
            DiffRow(left: [DiffSegment(kind: .delete, text: "c")], right: nil),
        ])
    }

    @Test func sideBySideMoreInsertsThanDeletes() {
        // A=["a"], B=["x","y","z"]; 行 diff: [del a, ins x, ins y, ins z]
        let r = DiffEngine.sideBySide("a", "x\ny\nz")
        #expect(r == [
            DiffRow(left: [DiffSegment(kind: .delete, text: "a")], right: [DiffSegment(kind: .insert, text: "x")]),
            DiffRow(left: nil, right: [DiffSegment(kind: .insert, text: "y")]),
            DiffRow(left: nil, right: [DiffSegment(kind: .insert, text: "z")]),
        ])
    }

    @Test func sideBySideTrailingNewline() {
        // "a\n"->["a",""], "a"->["a"]; 行 diff [equal a, delete ""]
        let r = DiffEngine.sideBySide("a\n", "a")
        #expect(r == [
            DiffRow(left: [DiffSegment(kind: .equal, text: "a")], right: [DiffSegment(kind: .equal, text: "a")]),
            DiffRow(left: [DiffSegment(kind: .delete, text: "")], right: nil),
        ])
    }

    @Test func sideBySideBothEmpty() {
        let r = DiffEngine.sideBySide("", "")
        #expect(r == [
            DiffRow(left: [DiffSegment(kind: .equal, text: "")], right: [DiffSegment(kind: .equal, text: "")]),
        ])
    }
```

- [ ] **Step 2: テストが失敗することを確認**

Run:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -destination 'platform=macOS' test 2>&1 | tail -20
```
Expected: コンパイルエラー（`DiffRow` / `sideBySide` が未定義）でビルド失敗。

- [ ] **Step 3: DiffRow と sideBySide を実装**

`Delta/Models/DiffEngine.swift` の `enum DiffEngine { ... }` の閉じ括弧の直前（`align` メソッドの後）に、以下のメソッドを追加:
```swift

    // MARK: - Side-by-side

    /// 行揃えの行ペア列を生成する。
    /// 1. 行 diff（既存）でユニファイドな行セグメント列を得る。
    /// 2. 連続する削除群と直後の挿入群をペアにし、各ペアは文字 diff（既存）で行内ハイライトを付ける。
    ///    余った削除/挿入は片側のみの行にする。
    static func sideBySide(_ textA: String, _ textB: String) -> [DiffRow] {
        let lineSegments = diff(textA, textB, mode: .line)
        var rows: [DiffRow] = []
        var index = 0
        while index < lineSegments.count {
            switch lineSegments[index].kind {
            case .equal:
                let line = lineSegments[index].text
                rows.append(DiffRow(
                    left: [DiffSegment(kind: .equal, text: line)],
                    right: [DiffSegment(kind: .equal, text: line)]
                ))
                index += 1
            case .delete:
                var deletes: [String] = []
                while index < lineSegments.count, lineSegments[index].kind == .delete {
                    deletes.append(lineSegments[index].text)
                    index += 1
                }
                var inserts: [String] = []
                while index < lineSegments.count, lineSegments[index].kind == .insert {
                    inserts.append(lineSegments[index].text)
                    index += 1
                }
                rows.append(contentsOf: pairRows(deletes: deletes, inserts: inserts))
            case .insert:
                var inserts: [String] = []
                while index < lineSegments.count, lineSegments[index].kind == .insert {
                    inserts.append(lineSegments[index].text)
                    index += 1
                }
                rows.append(contentsOf: pairRows(deletes: [], inserts: inserts))
            }
        }
        return rows
    }

    /// 削除行群と挿入行群を index 順にペアリングする。
    /// ペアは文字 diff で行内ハイライト、余りは片側のみの行。
    private static func pairRows(deletes: [String], inserts: [String]) -> [DiffRow] {
        var rows: [DiffRow] = []
        let pairCount = min(deletes.count, inserts.count)
        for k in 0..<pairCount {
            let charDiff = diff(deletes[k], inserts[k], mode: .character)
            let leftCell = charDiff.filter { $0.kind != .insert }   // equal + delete
            let rightCell = charDiff.filter { $0.kind != .delete }  // equal + insert
            rows.append(DiffRow(left: leftCell, right: rightCell))
        }
        for k in pairCount..<deletes.count {
            rows.append(DiffRow(left: [DiffSegment(kind: .delete, text: deletes[k])], right: nil))
        }
        for k in pairCount..<inserts.count {
            rows.append(DiffRow(left: nil, right: [DiffSegment(kind: .insert, text: inserts[k])]))
        }
        return rows
    }
```

そして同ファイルの先頭付近（`struct DiffSegment { ... }` の直後）に `DiffRow` を追加:
```swift

struct DiffRow: Equatable {
    let left: [DiffSegment]?    // nil = この行は左に存在しない（ギャップ）
    let right: [DiffSegment]?   // nil = この行は右に存在しない（ギャップ）
}
```

- [ ] **Step 4: テストが通ることを確認**

Run:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -destination 'platform=macOS' test 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`（既存 14 + 新規 9 = 23 テスト全通過）。新規ファイルは追加していないので `xcodegen generate` は不要。

- [ ] **Step 5: コミット**

```bash
git add Delta/Models/DiffEngine.swift DeltaTests/DiffEngineTests.swift
git commit -m "feat: DiffEngine に side-by-side 行ペア生成を追加"
```

---

### Task 2: 左右2ペイン表示への置換（SplitDiffView / DiffCellView / 向き切替）

ユニファイド表示（`DiffResultView`）を side-by-side 表示に置換し、左右/上下トグルを追加する。UI のためビルド＋手動確認で検証する。

**Files:**
- Create: `Delta/Views/SplitDiffView.swift`（`SplitOrientation` enum と2ペイン描画）
- Create: `Delta/Views/DiffCellView.swift`（1セル描画）
- Delete: `Delta/Views/DiffResultView.swift`
- Modify: `Delta/Views/DiffWindowView.swift`（Picker と結果ビューと state を差し替え）

**Interfaces:**
- Consumes: `DiffRow`、`DiffEngine.sideBySide(_:_:) -> [DiffRow]`、`DiffSegment`、`DiffKind`（Task 1）
- Produces:
  - `enum SplitOrientation: String { case horizontal; case vertical }`
  - `struct SplitDiffView: View { let rows: [DiffRow]; let orientation: SplitOrientation }`
  - `struct DiffCellView: View { let segments: [DiffSegment]? }`

- [ ] **Step 1: DiffCellView を作成**

Create `Delta/Views/DiffCellView.swift`:
```swift
import SwiftUI

/// side-by-side の1セル。nil はギャップ（行なし）。
/// 行全体の追加/削除はセル全幅を塗り、行内ハイライトは変更文字レンジのみ塗る。
struct DiffCellView: View {
    let segments: [DiffSegment]?

    var body: some View {
        Text(displayText)
            .font(.system(.body, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fullWidthBackground)
            .textSelection(.enabled)
    }

    private var fullWidthBackground: Color {
        guard let segments else { return .gray.opacity(0.08) }   // ギャップ（行なし）
        if segments.count == 1 {
            switch segments[0].kind {
            case .insert: return .green.opacity(0.3)              // 行全体追加
            case .delete: return .red.opacity(0.3)               // 行全体削除
            case .equal: return .clear
            }
        }
        return .clear                                            // 行内ハイライト or 共通
    }

    private var displayText: AttributedString {
        guard let segments else { return AttributedString(" ") } // ギャップ
        let joined = segments.map(\.text).joined()
        if joined.isEmpty { return AttributedString(" ") }       // 空行の高さ確保
        // 行全体の追加/削除は fullWidthBackground が塗るので素のテキスト。
        if segments.count == 1, segments[0].kind != .equal {
            return AttributedString(joined)
        }
        // 行内ハイライト: 変更文字レンジにのみ背景色。
        var result = AttributedString()
        for segment in segments {
            var piece = AttributedString(segment.text)
            switch segment.kind {
            case .equal: break
            case .insert: piece.backgroundColor = .green.opacity(0.3)
            case .delete: piece.backgroundColor = .red.opacity(0.3)
            }
            result.append(piece)
        }
        return result
    }
}
```

- [ ] **Step 2: SplitDiffView を作成**

Create `Delta/Views/SplitDiffView.swift`:
```swift
import SwiftUI

enum SplitOrientation: String {
    case horizontal
    case vertical
}

/// 行揃えの side-by-side 表示。
/// horizontal: 各行を HStack(左セル, 仕切り, 右セル) で並べ、行内で高さが揃うため折り返しても整列する。
/// vertical: 左ペイン（全行の左セル）を上、右ペインを下に積む。
struct SplitDiffView: View {
    let rows: [DiffRow]
    let orientation: SplitOrientation

    var body: some View {
        ScrollView {
            switch orientation {
            case .horizontal:
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .top, spacing: 0) {
                            DiffCellView(segments: row.left)
                            Divider()
                            DiffCellView(segments: row.right)
                        }
                    }
                }
            case .vertical:
                VStack(spacing: 0) {
                    pane { $0.left }
                    Divider()
                    pane { $0.right }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func pane(_ side: @escaping (DiffRow) -> [DiffSegment]?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                DiffCellView(segments: side(row))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

- [ ] **Step 3: 旧 DiffResultView を削除**

Run:
```bash
git rm Delta/Views/DiffResultView.swift
```

- [ ] **Step 4: DiffWindowView を side-by-side に差し替え**

Replace the entire contents of `Delta/Views/DiffWindowView.swift`:
```swift
import SwiftUI

struct DiffWindowView: View {
    @State private var textA = ""
    @State private var textB = ""
    @AppStorage("splitOrientation") private var orientation: SplitOrientation = .horizontal
    @State private var rows: [DiffRow] = []

    var body: some View {
        VStack(spacing: 8) {
            DiffEditorView(textA: $textA, textB: $textB)
                .frame(minHeight: 160)

            HStack {
                Picker("", selection: $orientation) {
                    Text("左右").tag(SplitOrientation.horizontal)
                    Text("上下").tag(SplitOrientation.vertical)
                }
                .pickerStyle(.segmented)
                .fixedSize()

                Spacer()

                Button("実行") { run() }
                    .keyboardShortcut(.return, modifiers: .command)
            }

            Divider()

            SplitDiffView(rows: rows, orientation: orientation)
        }
        .padding(12)
        .frame(minWidth: 480, minHeight: 420)
    }

    private func run() {
        rows = DiffEngine.sideBySide(textA, textB)
    }
}
```

注: `@AppStorage` は `RawRepresentable`（`RawValue == String`）の enum を直接保存できるため `SplitOrientation: String` で動く。`run()` は向きに依存しない（`sideBySide` は向きを取らない）ので、向き Picker の切替は再実行なしに即座にレイアウトへ反映される。

- [ ] **Step 5: プロジェクト再生成してビルド**

新規ファイル追加・ファイル削除があるため `xcodegen generate` が必須。

Run:
```bash
xcodegen generate && \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -configuration Debug -derivedDataPath build build 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: テストが通ることを確認**

Run:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -destination 'platform=macOS' test 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`（Task 1 の DiffEngine テストが引き続き通る）

- [ ] **Step 7: 手動で動作確認**

Run:
```bash
open build/Build/Products/Debug/Delta.app
```
確認手順（目視）:
1. メニューバー δ →「Open Diff Window」
2. A に `りんご\n色赤\nみかん`、B に `りんご\n色青\nぶどう` を入力 → 実行（⌘↵）
3. 「左右」: 左右2列で行が揃い、`色赤`/`色青` 行は「赤」「青」だけ着色、`みかん`(左赤全幅)/`ぶどう`(右緑全幅) がギャップ行とペア表示
4. 「上下」に切替（再実行なしで反映）: 上に A 全行・下に B 全行
5. アプリ再起動後も最後に選んだ向きが復元される（`@AppStorage`）

- [ ] **Step 8: コミット**

```bash
git add Delta/Views/SplitDiffView.swift Delta/Views/DiffCellView.swift Delta/Views/DiffWindowView.swift
git commit -m "feat: 左右/上下の side-by-side 差分表示に置換"
```

---

## 完了の定義

- `DiffEngine.sideBySide` の単体テストが緑（既存テストも維持、計 23）
- `xcodebuild build` 成功
- 手動確認（Task 2 Step 7）で左右/上下それぞれの行揃え・行内ハイライト・向き永続化が確認できる
- スコープ外（ホットキー・履歴・設定画面・賢い行ペアリング）は未着手
