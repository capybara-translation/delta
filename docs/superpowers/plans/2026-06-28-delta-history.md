# Delta 実行履歴 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Compare 実行時の入力を履歴に記録し、ツールバーの History ボタンのポップオーバーから過去の入力を呼び戻せるようにする（最大30件・再起動後も復元）。

**Architecture:** `@Observable` な `HistoryStore`（UserDefaults に JSON 永続化）を純粋ロジックとして TDD。`HistoryView`（ポップオーバー）と `DiffWindowView`（History ボタン＋記録＋読み戻し）で配線。

**Tech Stack:** Swift（言語モード5）/ SwiftUI / Observation / Swift Testing / XcodeGen。

## Global Constraints

- デプロイメントターゲット macOS 14.0 維持 / SWIFT_VERSION 5.0 / 外部 SPM 依存なし
- `DiffEngine`・`CodePointTextView`・`DiffEditorView`・`SplitDiffView`・`DiffCellView`・`DiffWindowManager`・`GlobalHotKey`・`SettingsView`・`CodePointFormatter`・`TabKeyResolver` は無変更
- ビルド・テストは `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` を前置
- **Swift ファイルを追加したら必ず `xcodegen generate`**（.xcodeproj は project.yml から生成、gitignore 済み）
- ビルド/テストの stderr の `IDESimulatorFoundation`/`[Connection]` 警告は無害。合否は `** BUILD SUCCEEDED **` / `** TEST SUCCEEDED **` 行で判断
- 履歴: 最大30件、新しい順、両方空は記録しない、直前エントリと完全一致なら記録しない

ビルドコマンド（参照）:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -configuration Debug -derivedDataPath build build
```
テストコマンド（参照）:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -destination 'platform=macOS' test
```

---

### Task 1: HistoryEntry と HistoryStore（純粋ロジック、TDD）

履歴のモデルと、追加（空/重複/上限）・消去・UserDefaults 永続化を行うストアを TDD で実装する。

**Files:**
- Create: `Delta/Models/HistoryEntry.swift`
- Create: `Delta/Store/HistoryStore.swift`
- Create: `DeltaTests/HistoryStoreTests.swift`

**Interfaces:**
- Consumes: なし（Swift 標準・Observation）
- Produces:
  - `struct HistoryEntry: Identifiable, Codable, Equatable { let id: UUID; let timestamp: Date; let textA: String; let textB: String }`
  - `@Observable final class HistoryStore { private(set) var entries: [HistoryEntry]; static let maxEntries = 30; init(userDefaults:key:); func add(textA:textB:date:); func clear() }`

- [ ] **Step 1: 失敗するテストを作成**

Create `DeltaTests/HistoryStoreTests.swift`:
```swift
import Testing
import Foundation
@testable import Delta

struct HistoryStoreTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test-history-\(UUID().uuidString)")!
    }

    @Test func addInsertsAtFront() {
        let store = HistoryStore(userDefaults: makeDefaults(), key: "h")
        store.add(textA: "a1", textB: "b1", date: Date(timeIntervalSince1970: 1))
        store.add(textA: "a2", textB: "b2", date: Date(timeIntervalSince1970: 2))
        #expect(store.entries.map(\.textA) == ["a2", "a1"])
    }

    @Test func skipsConsecutiveDuplicate() {
        let store = HistoryStore(userDefaults: makeDefaults(), key: "h")
        store.add(textA: "x", textB: "y", date: Date(timeIntervalSince1970: 1))
        store.add(textA: "x", textB: "y", date: Date(timeIntervalSince1970: 2))
        #expect(store.entries.count == 1)
    }

    @Test func skipsBothEmpty() {
        let store = HistoryStore(userDefaults: makeDefaults(), key: "h")
        store.add(textA: "", textB: "", date: Date(timeIntervalSince1970: 1))
        #expect(store.entries.isEmpty)
    }

    @Test func oneSideEmptyIsRecorded() {
        let store = HistoryStore(userDefaults: makeDefaults(), key: "h")
        store.add(textA: "x", textB: "", date: Date(timeIntervalSince1970: 1))
        #expect(store.entries.count == 1)
    }

    @Test func capsAtMaxEntries() {
        let store = HistoryStore(userDefaults: makeDefaults(), key: "h")
        for i in 0..<(HistoryStore.maxEntries + 5) {
            store.add(textA: "a\(i)", textB: "b\(i)", date: Date(timeIntervalSince1970: TimeInterval(i)))
        }
        #expect(store.entries.count == HistoryStore.maxEntries)
        #expect(store.entries.first?.textA == "a\(HistoryStore.maxEntries + 4)")
        #expect(store.entries.last?.textA == "a5")
    }

    @Test func nonConsecutiveDuplicateIsRecorded() {
        let store = HistoryStore(userDefaults: makeDefaults(), key: "h")
        store.add(textA: "x", textB: "y", date: Date(timeIntervalSince1970: 1))
        store.add(textA: "z", textB: "w", date: Date(timeIntervalSince1970: 2))
        store.add(textA: "x", textB: "y", date: Date(timeIntervalSince1970: 3))
        #expect(store.entries.count == 3)
    }

    @Test func persistsAcrossInstances() {
        let defaults = makeDefaults()
        let store1 = HistoryStore(userDefaults: defaults, key: "h")
        store1.add(textA: "p", textB: "q", date: Date(timeIntervalSince1970: 1))
        let store2 = HistoryStore(userDefaults: defaults, key: "h")
        #expect(store2.entries.map(\.textA) == ["p"])
    }

    @Test func clearEmptiesAndPersists() {
        let defaults = makeDefaults()
        let store1 = HistoryStore(userDefaults: defaults, key: "h")
        store1.add(textA: "p", textB: "q", date: Date(timeIntervalSince1970: 1))
        store1.clear()
        #expect(store1.entries.isEmpty)
        let store2 = HistoryStore(userDefaults: defaults, key: "h")
        #expect(store2.entries.isEmpty)
    }

    @Test func recordsTimestamp() {
        let store = HistoryStore(userDefaults: makeDefaults(), key: "h")
        let d = Date(timeIntervalSince1970: 12345)
        store.add(textA: "a", textB: "b", date: d)
        #expect(store.entries.first?.timestamp == d)
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
Expected: コンパイルエラー（`cannot find 'HistoryStore' / 'HistoryEntry' in scope`）でビルド失敗。

- [ ] **Step 3: HistoryEntry を実装**

Create `Delta/Models/HistoryEntry.swift`:
```swift
import Foundation

/// One recorded comparison: the two input texts and when they were compared.
struct HistoryEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let textA: String
    let textB: String
}
```

- [ ] **Step 4: HistoryStore を実装**

Create `Delta/Store/HistoryStore.swift`:
```swift
import Foundation
import Observation

/// Stores recent comparison inputs (newest first, capped), persisted to UserDefaults as JSON.
@Observable
final class HistoryStore {
    static let maxEntries = 30

    private(set) var entries: [HistoryEntry]

    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private let key: String

    init(userDefaults: UserDefaults = .standard, key: String = "history") {
        self.userDefaults = userDefaults
        self.key = key
        if let data = userDefaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            entries = decoded
        } else {
            entries = []
        }
    }

    /// Records a comparison. Skips when both texts are empty, or when it equals the most recent entry.
    func add(textA: String, textB: String, date: Date) {
        if textA.isEmpty && textB.isEmpty { return }
        if let latest = entries.first, latest.textA == textA, latest.textB == textB { return }
        entries.insert(HistoryEntry(id: UUID(), timestamp: date, textA: textA, textB: textB), at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            userDefaults.set(data, forKey: key)
        }
    }
}
```

- [ ] **Step 5: テストが通ることを確認**

Run:
```bash
xcodegen generate && \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -destination 'platform=macOS' test 2>&1 | tail -25
```
Expected: `** TEST SUCCEEDED **`（既存39 + 新規9 = 48 全通過）

- [ ] **Step 6: コミット**

```bash
git add Delta/Models/HistoryEntry.swift Delta/Store/HistoryStore.swift DeltaTests/HistoryStoreTests.swift
git commit -m "feat: 履歴モデルと HistoryStore（追加/上限/永続化）"
```

---

### Task 2: HistoryView とポップオーバー配線

History ボタンのポップオーバーで一覧・選択・Clear し、Compare 時に記録する。UI のためビルド＋手動確認で検証する。

**Files:**
- Create: `Delta/Views/HistoryView.swift`
- Modify: `Delta/Views/DiffWindowView.swift`（全置換）

**Interfaces:**
- Consumes: `HistoryStore`、`HistoryEntry`（Task 1）、`DiffEngine.sideBySide`、`SplitOrientation`
- Produces:
  - `struct HistoryView: View { let store: HistoryStore; var onSelect: (HistoryEntry) -> Void }`

- [ ] **Step 1: HistoryView を作成**

Create `Delta/Views/HistoryView.swift`:
```swift
import SwiftUI

/// Popover content listing recent comparisons. Selecting an entry calls onSelect; Clear empties the store.
struct HistoryView: View {
    let store: HistoryStore
    var onSelect: (HistoryEntry) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("History").font(.headline)
                Spacer()
                Button("Clear") { store.clear() }
                    .disabled(store.entries.isEmpty)
            }
            .padding(8)

            Divider()

            if store.entries.isEmpty {
                Text("No history")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(store.entries) { entry in
                    Button {
                        onSelect(entry)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.timestamp, format: .dateTime.month().day().hour().minute().second())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(preview(entry))
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 360, height: 320)
    }

    private func preview(_ entry: HistoryEntry) -> String {
        let a = entry.textA.replacingOccurrences(of: "\n", with: " ")
        let b = entry.textB.replacingOccurrences(of: "\n", with: " ")
        return "A: \(a)  B: \(b)"
    }
}
```

- [ ] **Step 2: DiffWindowView を全置換**

Replace the entire contents of `Delta/Views/DiffWindowView.swift`:
```swift
import SwiftUI

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

                Button("Compare") { run() }
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
        history.add(textA: textA, textB: textB, date: Date())
    }
}
```

- [ ] **Step 3: プロジェクト再生成してビルド**

新規ファイル追加のため `xcodegen generate` が必須。

Run:
```bash
xcodegen generate && \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -configuration Debug -derivedDataPath build build 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: テストが引き続き通ることを確認**

Run:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -destination 'platform=macOS' test 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`（48 全通過）

- [ ] **Step 5: 起動して手動確認**

新バイナリで確認するため旧プロセスを止めてから開く:
```bash
pkill -x Delta; sleep 1
open build/Build/Products/Debug/Delta.app && sleep 2 && pgrep -x Delta
```
プロセスが生きていること（即クラッシュしないこと）を確認。実装者はここまで（プロセス生存）を報告する。以降はコントローラ/ユーザーが確認する:
1. A/B に入力し Compare → History ボタンのポップオーバーに1件増える
2. 同じ内容で再度 Compare → 増えない。内容を変えて Compare → 増える
3. ポップオーバーのエントリを選択 → A/B に読み込まれる（再実行はされない）
4. Clear で空になる。アプリ再起動後も履歴が残る（Clear 前）
5. 既存の diff・コードポイント表示・Tab・⌃⌥D・設定が引き続き動く

- [ ] **Step 6: コミット**

```bash
git add Delta/Views/HistoryView.swift Delta/Views/DiffWindowView.swift
git commit -m "feat: 履歴ポップオーバーと記録/読み戻しの配線"
```

---

## 完了の定義

- `HistoryStore` の単体テスト9件＋既存39件が緑（計48、`** TEST SUCCEEDED **`）
- `xcodebuild build` 成功
- 手動確認（Task 2 Step 5）で 記録/重複スキップ/読み戻し/Clear/再起動復元 が動く
- デプロイメントターゲット macOS 14・既存機能・diff ロジックは無変更
