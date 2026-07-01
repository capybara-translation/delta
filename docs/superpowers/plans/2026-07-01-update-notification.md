# Update Notification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Notify the user when a newer release exists on GitHub — show `Update available (vX.Y.Z)` in the menu-bar menu (launch check) and report via an alert on a manual "Check for Updates…", both opening the Releases page in the browser. No auto-update.

**Architecture:** A pure `VersionComparator` and a `Decodable` `GitHubRelease` handle the logic; a `@MainActor @Observable UpdateChecker` fetches `releases/latest` with `URLSession`, updates observable state (launch, silent) or shows an `NSAlert` (manual), and opens the Releases page with `NSWorkspace`. `MenuContent`, `AppDelegate`, and `SettingsView` wire it in.

**Tech Stack:** Swift, SwiftUI, AppKit (NSAlert/NSWorkspace/NSApplication), Observation (`@Observable`), URLSession, Swift Testing (`import Testing`).

## Global Constraints

- No external dependencies — system frameworks only.
- Swift 5.0, macOS 14 target.
- Repo: `capybara-translation/delta`. API: `https://api.github.com/repos/capybara-translation/delta/releases/latest`. Releases page: `https://github.com/capybara-translation/delta/releases/latest`.
- GitHub API requires a `User-Agent` header (no UA → 403). Also send `Accept: application/vnd.github+json`.
- Version compare: strip a leading `v`/`V`, then `String.compare(options: .numeric)`; newer means `.orderedDescending`.
- Launch check runs only when `UserDefaults` key `checkForUpdatesOnLaunch` is true (missing = true). Launch failures are silent. Manual check always runs and always reports via alert.
- Current version: `Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""`.
- `@Observable` types import `Foundation` + `Observation` (see existing `Delta/Store/HistoryStore.swift`).
- Run `xcodegen generate` after adding new files (Tasks 1 & 2 add files) before building/testing.

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

### Task 1: Pure helpers — VersionComparator + GitHubRelease

**Files:**
- Create: `Delta/Update/VersionComparator.swift`
- Create: `Delta/Update/GitHubRelease.swift`
- Test: `DeltaTests/VersionComparatorTests.swift`
- Test: `DeltaTests/GitHubReleaseTests.swift`

**Interfaces:**
- Produces:
  - `enum VersionComparator { static func isNewer(latestTag: String, currentVersion: String) -> Bool }`
  - `struct GitHubRelease: Decodable { let tagName: String }` (decodes JSON key `tag_name`)

- [ ] **Step 1: Write the failing tests**

`DeltaTests/VersionComparatorTests.swift`:
```swift
import Testing
@testable import Delta

struct VersionComparatorTests {
    @Test func newerPatchIsNewer() {
        #expect(VersionComparator.isNewer(latestTag: "v1.3.1", currentVersion: "1.3.0"))
    }
    @Test func comparesNumericallyNotLexically() {
        #expect(VersionComparator.isNewer(latestTag: "v1.10.0", currentVersion: "1.9.0"))
    }
    @Test func equalIsNotNewer() {
        #expect(!VersionComparator.isNewer(latestTag: "v1.3.0", currentVersion: "1.3.0"))
    }
    @Test func olderIsNotNewer() {
        #expect(!VersionComparator.isNewer(latestTag: "v1.2.0", currentVersion: "1.3.0"))
    }
    @Test func handlesMixedVPrefix() {
        #expect(VersionComparator.isNewer(latestTag: "1.3.1", currentVersion: "v1.3.0"))
    }
}
```

`DeltaTests/GitHubReleaseTests.swift`:
```swift
import Testing
import Foundation
@testable import Delta

struct GitHubReleaseTests {
    @Test func decodesTagNameFromGitHubJSON() throws {
        let json = #"{"tag_name":"v1.3.1","name":"v1.3.1","draft":false,"prerelease":false}"#.data(using: .utf8)!
        let release = try JSONDecoder().decode(GitHubRelease.self, from: json)
        #expect(release.tagName == "v1.3.1")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run `xcodegen generate`, then the test command. Expected: FAIL — `VersionComparator` and `GitHubRelease` are not defined.

- [ ] **Step 3: Write the implementations**

`Delta/Update/VersionComparator.swift`:
```swift
import Foundation

/// Compares release version strings. Strips a leading "v"/"V" and compares
/// numerically so that, e.g., 1.10.0 is newer than 1.9.0.
enum VersionComparator {
    /// True if `latestTag` is a strictly newer version than `currentVersion`.
    static func isNewer(latestTag: String, currentVersion: String) -> Bool {
        strip(latestTag).compare(strip(currentVersion), options: .numeric) == .orderedDescending
    }

    private static func strip(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        if let first = t.first, first == "v" || first == "V" { t.removeFirst() }
        return t
    }
}
```

`Delta/Update/GitHubRelease.swift`:
```swift
/// The subset of a GitHub release we care about (its tag, e.g. "v1.3.1").
struct GitHubRelease: Decodable {
    let tagName: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run the test command. Expected: PASS — the five `VersionComparator` tests and the `GitHubRelease` decode test pass; the whole suite stays green.

- [ ] **Step 5: Commit**

```bash
git add Delta/Update/VersionComparator.swift Delta/Update/GitHubRelease.swift \
        DeltaTests/VersionComparatorTests.swift DeltaTests/GitHubReleaseTests.swift
git commit -m "feat: 更新チェックの純粋ロジック（VersionComparator・GitHubRelease）"
```

---

### Task 2: UpdateChecker (fetch, compare, alert, open)

**Files:**
- Create: `Delta/Update/UpdateChecker.swift`

**Interfaces:**
- Consumes: `VersionComparator.isNewer(latestTag:currentVersion:)`, `GitHubRelease` (Task 1).
- Produces:
  - `@MainActor @Observable final class UpdateChecker` with `static let shared`
  - `private(set) var latestVersion: String?`, `private(set) var isUpdateAvailable: Bool`
  - `func checkOnLaunch()`, `func checkManually()`, `func openReleasesPage()`
  - `static let releasesURL: URL`

No unit test: this orchestrates `URLSession`, `NSAlert`, and `NSWorkspace` (side effects). The decision logic it relies on is already tested in Task 1. Verify by building and the manual checks in Task 3.

- [ ] **Step 1: Write the implementation**

`Delta/Update/UpdateChecker.swift`:
```swift
import AppKit
import Observation

/// Checks GitHub Releases for a newer version. Launch checks update observable
/// state silently; manual checks report the outcome via an alert. Never installs
/// anything — it only points the user at the Releases page.
@MainActor
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    static let releasesURL = URL(string: "https://github.com/capybara-translation/delta/releases/latest")!
    private static let apiURL = URL(string: "https://api.github.com/repos/capybara-translation/delta/releases/latest")!

    private(set) var latestVersion: String?
    private(set) var isUpdateAvailable = false

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    private init() {}

    /// Called at launch. Runs only when the "check on launch" preference is on
    /// (missing key defaults to true). Failures are silent.
    func checkOnLaunch() {
        let enabled = UserDefaults.standard.object(forKey: "checkForUpdatesOnLaunch") as? Bool ?? true
        guard enabled else { return }
        Task { try? await refresh() }
    }

    /// Manual check from the menu. Always runs; always reports via an alert.
    func checkManually() {
        Task {
            do {
                try await refresh()
                if isUpdateAvailable, let latest = latestVersion {
                    showUpdateAlert(latest: latest)
                } else {
                    showUpToDateAlert()
                }
            } catch {
                showErrorAlert()
            }
        }
    }

    func openReleasesPage() {
        NSWorkspace.shared.open(Self.releasesURL)
    }

    /// Fetches the latest release, decodes it, and updates state. Throws on failure.
    private func refresh() async throws {
        var request = URLRequest(url: Self.apiURL)
        request.setValue("Delta-Diff", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        latestVersion = release.tagName
        isUpdateAvailable = VersionComparator.isNewer(latestTag: release.tagName, currentVersion: currentVersion)
    }

    private func showUpdateAlert(latest: String) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Update available"
        alert.informativeText = "A new version (\(latest)) is available."
        alert.addButton(withTitle: "Open Releases")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            openReleasesPage()
        }
    }

    private func showUpToDateAlert() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "You're up to date"
        alert.informativeText = "Delta Diff \(currentVersion) is the latest version."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showErrorAlert() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Couldn't check for updates"
        alert.informativeText = "Please try again later."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
```

- [ ] **Step 2: Regenerate and build**

Run `xcodegen generate`, then the build command. Expected: compiles.

- [ ] **Step 3: Run the full test suite**

Run the test command. Expected: PASS — no regressions (Task 1 tests still green).

- [ ] **Step 4: Commit**

```bash
git add Delta/Update/UpdateChecker.swift
git commit -m "feat: UpdateChecker（GitHub Releases 取得・比較・通知・ページ表示）"
```

---

### Task 3: Wire into menu, launch, and Settings

**Files:**
- Modify: `Delta/DeltaApp.swift`
- Modify: `Delta/Views/SettingsView.swift`

**Interfaces:**
- Consumes: `UpdateChecker.shared` (`isUpdateAvailable`, `latestVersion`, `checkManually()`, `checkOnLaunch()`, `openReleasesPage()`).

No unit test: SwiftUI/menu wiring and a launch-time call. Verify by building, running the full suite, and the manual checks.

- [ ] **Step 1: Update MenuContent and AppDelegate in DeltaApp.swift**

Replace the `MenuContent` struct and the `applicationDidFinishLaunching` method in `Delta/DeltaApp.swift`.

`MenuContent` becomes:
```swift
private struct MenuContent: View {
    @Environment(\.openSettings) private var openSettings
    @State private var updateChecker = UpdateChecker.shared

    var body: some View {
        if updateChecker.isUpdateAvailable, let latest = updateChecker.latestVersion {
            Button("Update available (\(latest))") { updateChecker.openReleasesPage() }
            Divider()
        }
        Button("Open Delta Diff…") { DiffWindowManager.shared.show() }
        Button("Settings…") {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openSettings()
        }
        Button("Check for Updates…") { updateChecker.checkManually() }
        Divider()
        Button("Quit Delta Diff") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
```

`applicationDidFinishLaunching` becomes:
```swift
    func applicationDidFinishLaunching(_ notification: Notification) {
        clearTextIfNeeded()
        HotKeyController.shared.start()
        UpdateChecker.shared.checkOnLaunch()
    }
```

(No new import: `DeltaApp.swift` already uses `NSApplication` with only `import SwiftUI`.)

- [ ] **Step 2: Add the Settings toggle in SettingsView.swift**

In `Delta/Views/SettingsView.swift`, add this stored property alongside the other `@AppStorage`/`@State` properties at the top of `struct SettingsView`:
```swift
    @AppStorage("checkForUpdatesOnLaunch") private var checkForUpdatesOnLaunch = true
```
And add this toggle to the `Form`, immediately after the existing `Toggle("Keep text between launches", isOn: $keepText)` line:
```swift
            Toggle("Check for updates on launch", isOn: $checkForUpdatesOnLaunch)
```

- [ ] **Step 3: Regenerate, build, and run the full suite**

Run `xcodegen generate` (no new files, but safe), then the build command (expected: compiles) and the test command (expected: PASS — no regressions).

- [ ] **Step 4: Manual verification**

Because the current app version equals the latest release, the "update available" path needs a lower version to trigger. Build a Debug app with a lowered marketing version to simulate an outdated install:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Delta.xcodeproj -scheme Delta -configuration Debug \
  -derivedDataPath build MARKETING_VERSION=1.0.0 build
open build/Build/Products/Debug/Delta.app
```
Verify:
1. Open the menu — with the network up and "check on launch" on, `Update available (vX.Y.Z)` appears at the top. Click it → the Releases page opens in the default browser.
2. Choose **Check for Updates…** → an alert "A new version (vX.Y.Z) is available." with **Open Releases** / **Later**; Open Releases opens the page.
3. Open **Settings…**, turn **Check for updates on launch** off, quit and relaunch (same lowered-version build): the menu no longer shows the update item on launch, but **Check for Updates…** still works.
4. Turn airplane mode on (or disconnect network), choose **Check for Updates…** → alert "Couldn't check for updates."
5. Build normally (current version, no `MARKETING_VERSION` override) and choose **Check for Updates…** → alert "You're up to date".

- [ ] **Step 5: Commit**

```bash
git add Delta/DeltaApp.swift Delta/Views/SettingsView.swift
git commit -m "feat: メニューと起動時チェック・Settings トグルに更新通知を配線"
```

---

## Notes for the implementer

- Keep all new update files under `Delta/Update/`.
- Do not add any network library — `URLSession` only.
- After this plan, consider a version bump + release only when the user asks.
