# Delta スカラー敏感 diff Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `DiffEngine` の一致判定を Unicode 正準等価から「Unicode スカラー列の一致」へ変え、NFC/NFD など符号化違いを常に差分として検出できるようにする。

**Architecture:** スカラー列で `==`/`hash` する内部トークン型 `ExactToken` を導入し、`tokenize`/`align` の比較基盤を `[String]` から `[ExactToken]` に差し替える。行・文字の両モードが同じ `tokenize`/`align` を通るため両方が符号化敏感になる。公開 API（`diff`/`sideBySide`）と `DiffSegment`・View 層は無変更。

**Tech Stack:** Swift（言語モード5）/ Swift Testing / XcodeGen。

## Global Constraints

- 変更は `Delta/Models/DiffEngine.swift` と `DeltaTests/DiffEngineTests.swift` のみ。`DiffMode`/`DiffKind`/`DiffSegment`/`DiffRow` と `diff(_:_:mode:)`/`sideBySide(_:_:)` の公開シグネチャは不変
- 比較は**常に**スカラー列の一致（トグルなし）。**行・文字の両方**に適用
- ハイライト粒度は書記素クラスタ（見た目の1文字）単位を維持（トークン化規則は変えない）
- 既存23テストは不変で緑（リグレッションなし）
- macOS 14.0 / SWIFT_VERSION 5.0 / 外部 SPM 依存なし
- ビルド・テストは `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` を前置
- 新規ファイルの追加・削除はなし（既存2ファイルの編集のみ）なので `xcodegen generate` は不要
- ビルド/テストの stderr の `IDESimulatorFoundation`/`[Connection]` 警告は無害。合否は `** TEST SUCCEEDED **` 行で判断

テストコマンド（参照）:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -destination 'platform=macOS' test
```

---

### Task 1: DiffEngine の比較をスカラー敏感にする（TDD）

`tokenize`/`align` の比較基盤を `ExactToken`（スカラー基準の Hashable）に差し替える。検出が符号化に敏感になり、NFC/NFD 違いが差分として現れる。表示・公開 API は不変。

**Files:**
- Modify: `Delta/Models/DiffEngine.swift`
- Modify: `DeltaTests/DiffEngineTests.swift`（`struct DiffEngineTests` 内に3テスト追加）

**Interfaces:**
- Consumes（既存・不変）: `DiffEngine.diff(_:_:mode:) -> [DiffSegment]`、`DiffEngine.sideBySide(_:_:) -> [DiffRow]`、`DiffSegment`、`DiffRow`、`DiffKind`
- Produces: 公開 API の変更なし（内部実装のみ変更）。挙動変更＝符号化違いを検出する。

- [ ] **Step 1: 失敗するテストを追加**

`DeltaTests/DiffEngineTests.swift` の `struct DiffEngineTests { ... }` の閉じ括弧の直前に追加:
```swift
    // MARK: - スカラー敏感（符号化差の検出）

    @Test func characterDiffDetectsNFCvsNFD() {
        // NFC「ờ」= U+1EDD（1スカラー）, NFD「ờ」= U+006F U+031B U+0300（3スカラー）。
        // 正準等価だが符号化が違うので、スカラー比較では差分になる。
        let nfc = "\u{1EDD}"
        let nfd = "\u{006F}\u{031B}\u{0300}"
        let r = DiffEngine.diff(nfc, nfd, mode: .character)
        #expect(r == [
            DiffSegment(kind: .delete, text: nfc),
            DiffSegment(kind: .insert, text: nfd),
        ])
    }

    @Test func sideBySideDetectsNFCvsNFD() {
        // 1行中で「ờ」だけ符号化が違う。行も符号化敏感に検出され、行内で「ờ」がハイライトされる。
        let nfc = "\u{1EDD}"
        let nfd = "\u{006F}\u{031B}\u{0300}"
        let r = DiffEngine.sideBySide("A" + nfc + "B", "A" + nfd + "B")
        #expect(r == [
            DiffRow(
                left: [
                    DiffSegment(kind: .equal, text: "A"),
                    DiffSegment(kind: .delete, text: nfc),
                    DiffSegment(kind: .equal, text: "B"),
                ],
                right: [
                    DiffSegment(kind: .equal, text: "A"),
                    DiffSegment(kind: .insert, text: nfd),
                    DiffSegment(kind: .equal, text: "B"),
                ]
            ),
        ])
    }

    @Test func identicalScalarsStillEqual() {
        // 同じスカラー列は引き続き差分なし（リグレッション確認）。
        let r = DiffEngine.diff("abc", "abc", mode: .character)
        #expect(r == [
            DiffSegment(kind: .equal, text: "a"),
            DiffSegment(kind: .equal, text: "b"),
            DiffSegment(kind: .equal, text: "c"),
        ])
    }
```

- [ ] **Step 2: テストが失敗することを確認**

Run:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -destination 'platform=macOS' test 2>&1 | tail -25
```
Expected: ビルドは成功するが、`characterDiffDetectsNFCvsNFD` と `sideBySideDetectsNFCvsNFD` の2件が**アサーション失敗**（現状は正準等価で「同じ」とみなされ、`[.equal ...]` が返るため）。`identicalScalarsStillEqual` は通る。`** TEST FAILED **`。

- [ ] **Step 3: ExactToken を導入し tokenize/align を差し替える**

`Delta/Models/DiffEngine.swift` で次の3点を変更する。

(a) `struct DiffSegment { ... }` の直後（`struct DiffRow` の前）に `ExactToken` を追加:
```swift

/// 正準等価ではなく Unicode スカラー列で一致を判定するトークン。
/// Swift の String/Character の == は正準等価のため NFC/NFD 等を区別できない。
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

(b) `tokenize` を `[ExactToken]` を返すよう変更（`private` に下げる）。既存の `tokenize` メソッド全体を次で置換:
```swift
    /// 行モードは改行を維持するため空サブシーケンスを残す。
    /// 文字モードは書記素クラスタ（Swift Character）単位でトークン化する。
    /// 比較は ExactToken により Unicode スカラー列で行う（正準等価では判定しない）。
    private static func tokenize(_ text: String, mode: DiffMode) -> [ExactToken] {
        switch mode {
        case .line:
            return text.split(separator: "\n", omittingEmptySubsequences: false)
                .map { ExactToken(text: String($0)) }
        case .character:
            return text.map { ExactToken(text: String($0)) }
        }
    }
```

(c) `align` の引数型を `[ExactToken]` に変更し（`private` に下げる）、`DiffSegment` 構築時に `.text` を使う。既存の `align` メソッド全体を次で置換:
```swift
    /// CollectionDifference の removals/insertions から、
    /// 削除→挿入→共通の順で 1 列のユニファイドなセグメント列を再構成する。
    ///
    /// 不変条件: 変更ブロック内では必ず削除群が挿入群より先に出る（削除判定を
    /// 挿入判定より前に行うため）。`sideBySide` はこの順序に依存して削除/挿入を
    /// ペアリングするので、この分岐順を変えないこと。
    private static func align(_ a: [ExactToken], _ b: [ExactToken]) -> [DiffSegment] {
        let difference = b.difference(from: a)
        var removedOffsets = Set<Int>()
        var insertedOffsets = Set<Int>()
        for change in difference {
            switch change {
            case let .remove(offset, _, _): removedOffsets.insert(offset)
            case let .insert(offset, _, _): insertedOffsets.insert(offset)
            }
        }

        var segments: [DiffSegment] = []
        var i = 0
        var j = 0
        while i < a.count || j < b.count {
            if i < a.count, removedOffsets.contains(i) {
                segments.append(DiffSegment(kind: .delete, text: a[i].text))
                i += 1
            } else if j < b.count, insertedOffsets.contains(j) {
                segments.append(DiffSegment(kind: .insert, text: b[j].text))
                j += 1
            } else if i < a.count, j < b.count {
                segments.append(DiffSegment(kind: .equal, text: a[i].text))
                i += 1
                j += 1
            } else if i < a.count {
                segments.append(DiffSegment(kind: .delete, text: a[i].text))
                i += 1
            } else {
                segments.append(DiffSegment(kind: .insert, text: b[j].text))
                j += 1
            }
        }
        return segments
    }
```

注: `diff(_:_:mode:)` は `tokenize`→`align` を呼ぶだけで変更不要（`[ExactToken]` を渡して受け取る形になる）。`sideBySide`/`pairRows` も内部で `diff` を呼ぶだけなので変更不要。`CollectionDifference` は `ExactToken: Hashable` を要求するが、上で `Hashable` 準拠済み。

- [ ] **Step 4: テストが通ることを確認**

Run:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Delta.xcodeproj -scheme Delta -destination 'platform=macOS' test 2>&1 | tail -25
```
Expected: `** TEST SUCCEEDED **`（既存23 + 新規3 = 26 全通過）。`align`/`tokenize` を `private` に下げても、呼び出しは同ファイル内の `diff` のみなのでビルドは通る。

- [ ] **Step 5: コミット**

```bash
git add Delta/Models/DiffEngine.swift DeltaTests/DiffEngineTests.swift
git commit -m "feat: diff の一致判定を Unicode スカラー敏感にする（NFC/NFD 等を検出）"
```

---

## 完了の定義

- 新規3テスト＋既存23テストが緑（計26、`** TEST SUCCEEDED **`）
- NFC/NFD の符号化違いが `diff`/`sideBySide` で差分として検出される
- 公開 API・`DiffSegment`・View 層は無変更
- 手動確認（任意）: 実際の NFC/NFD 入力を A/B に入れて実行し、side-by-side に行内ハイライトが出る
