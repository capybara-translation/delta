# Code-Point Full Copy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Copy code points" context-menu action to each input box's code-point line that copies the full (non-truncated) `U+XXXX …` list to the clipboard, while the on-screen display keeps its existing truncation.

**Architecture:** Add a pure `CodePointFormatter.fullList(_:)` that never truncates (peer of the existing `describe`). `DiffEditorView` holds the raw selected string per box, derives the (truncated) display via `describe`, and copies `fullList` to `NSPasteboard` from a `.contextMenu`.

**Tech Stack:** Swift, SwiftUI, AppKit (`NSPasteboard`), Swift Testing (`import Testing`).

## Global Constraints

- No external dependencies — system frameworks only.
- Swift 5.0, macOS 14 target.
- Copy format equals the display format, but complete: `U+XXXX` per scalar, space-separated, and when there is exactly one scalar its Unicode name is appended. No `… (+N)` truncation suffix.
- The on-screen code-point display keeps its existing truncation (`CodePointFormatter.maxScalars` = 24) unchanged.
- Neither task adds a new file, so `xcodegen generate` is not required; build/test directly.

**Build command:**
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Delta.xcodeproj -scheme Delta -destination 'platform=macOS' build
```
**Test command:**
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Delta.xcodeproj -scheme Delta -destination 'platform=macOS' test
```

---

### Task 1: CodePointFormatter.fullList (non-truncating list)

**Files:**
- Modify: `Delta/Models/CodePointFormatter.swift`
- Test: `DeltaTests/CodePointFormatterTests.swift` (append)

**Interfaces:**
- Consumes: the existing private `CodePointFormatter.hex(_:)` and the existing `describe(_:)` (for the contrast test).
- Produces: `CodePointFormatter.fullList(_ text: String) -> String` — lists every scalar as `U+XXXX` space-separated, never truncating; appends the Unicode name only when there is exactly one scalar; empty input returns `""`.

- [ ] **Step 1: Write the failing tests**

Append these tests inside `struct CodePointFormatterTests` in `DeltaTests/CodePointFormatterTests.swift` (before the closing `}`):

```swift
    @Test func fullListEmptyIsEmpty() {
        #expect(CodePointFormatter.fullList("") == "")
    }

    @Test func fullListSingleHasName() {
        #expect(CodePointFormatter.fullList("A") == "U+0041 LATIN CAPITAL LETTER A")
    }

    @Test func fullListMultipleHasNoName() {
        #expect(CodePointFormatter.fullList("AB") == "U+0041 U+0042")
    }

    @Test func fullListDoesNotTruncateBeyondMax() {
        // 30 scalars exceeds maxScalars (24). fullList must contain all 30 and no
        // truncation marker, whereas describe truncates the same input.
        let input = String(repeating: "a", count: 30)
        let full = CodePointFormatter.fullList(input)
        let expected = Array(repeating: "U+0061", count: 30).joined(separator: " ")
        #expect(full == expected)
        #expect(!full.contains("…"))
        #expect(CodePointFormatter.describe(input).contains("… (+"))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run the test command. Expected: FAIL — `fullList` is not a member of `CodePointFormatter` (compile error / unresolved reference).

- [ ] **Step 3: Add the implementation**

In `Delta/Models/CodePointFormatter.swift`, add `fullList` immediately after the `describe(_:)` method (before the `private static func hex`):

```swift
    /// Lists every scalar as "U+XXXX" (space-separated), never truncating.
    /// When there is exactly one scalar, appends its Unicode name (same as `describe`).
    /// Empty input returns an empty string.
    static func fullList(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        if scalars.isEmpty { return "" }

        var parts = scalars.map(hex)
        if scalars.count == 1, let name = scalars[0].properties.name, !name.isEmpty {
            parts[0] += " " + name
        }
        return parts.joined(separator: " ")
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run the test command. Expected: PASS — the four new `fullList*` tests pass and the whole suite stays green.

- [ ] **Step 5: Commit**

```bash
git add Delta/Models/CodePointFormatter.swift DeltaTests/CodePointFormatterTests.swift
git commit -m "feat: CodePointFormatter.fullList（切り詰めなしの全スカラー列）"
```

---

### Task 2: DiffEditorView — "Copy code points" context menu

**Files:**
- Modify: `Delta/Views/DiffEditorView.swift`

**Interfaces:**
- Consumes: `CodePointFormatter.describe(_:)` (display) and `CodePointFormatter.fullList(_:)` (copy) from Task 1; existing `CodePointTextView`, `EditorField`, `FocusLink`.

No unit test: this is SwiftUI wiring plus an `NSPasteboard` side effect. The copy format is already covered by Task 1's `fullList` tests. Verify by building, running the full suite (no regressions), and the manual check below.

- [ ] **Step 1: Replace DiffEditorView.swift with the context-menu version**

Replace the entire contents of `Delta/Views/DiffEditorView.swift` with:

```swift
import SwiftUI
import AppKit

struct DiffEditorView: View {
    @Binding var textA: String
    @Binding var textB: String
    @State private var selectionA: String = ""
    @State private var selectionB: String = ""
    @State private var focusLink = FocusLink()

    var body: some View {
        HStack(spacing: 8) {
            editor("A", field: .a, text: $textA, selection: $selectionA)
            editor("B", field: .b, text: $textB, selection: $selectionB)
        }
    }

    private func editor(_ label: String, field: EditorField, text: Binding<String>, selection: Binding<String>) -> some View {
        // Display keeps the existing truncation; the copy action uses the full list.
        let display = CodePointFormatter.describe(selection.wrappedValue)
        return VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            CodePointTextView(text: text, field: field, focusLink: focusLink) { selected in
                selection.wrappedValue = selected
            }

            Text(display.isEmpty ? " " : display)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .contextMenu {
                    Button("Copy code points") {
                        copyCodePoints(selection.wrappedValue)
                    }
                    .disabled(selection.wrappedValue.isEmpty)
                }
        }
    }

    private func copyCodePoints(_ selected: String) {
        let full = CodePointFormatter.fullList(selected)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(full, forType: .string)
    }
}
```

- [ ] **Step 2: Build and run the full test suite**

Run the build command (expected: compiles) and the test command (expected: PASS — no regressions; Task 1's tests still green).

- [ ] **Step 3: Manual verification**

Build and launch the Debug app:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Delta.xcodeproj -scheme Delta -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/Delta.app
```
Open the diff window and verify:
1. Select a run of 30+ characters in an input box. The code-point line still shows the truncated `… (+N)` display.
2. Right-click the code-point line → **Copy code points**.
3. Paste into another app: the pasted text lists **all** code points (`U+XXXX …`), with no `…` marker.
4. Select a single character (e.g. `A`): Copy code points yields `U+0041 LATIN CAPITAL LETTER A`.
5. With nothing selected, the code-point line is blank and the **Copy code points** menu item is disabled.

- [ ] **Step 4: Commit**

```bash
git add Delta/Views/DiffEditorView.swift
git commit -m "feat: コードポイント表示欄に「Copy code points」（全件コピー）を追加"
```

---

## Notes for the implementer

- Do not change `describe(_:)` or `maxScalars`; the display truncation is intentional and covered by existing tests.
- After this plan, consider a version bump + release only when the user asks.
