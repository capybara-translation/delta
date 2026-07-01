# Delta Diff 更新通知（GitHub Releases チェック）設計 (2026-07-01)

GitHub Releases に新しいバージョンが出たら、メニューバーのメニューに `Update available (vX.Y.Z)` を表示し、クリックで Releases ページをブラウザで開く。加えて手動「Check for Updates…」でアラート応答する。**実際の自動更新は行わない**（通知＋ページを開くだけ）。外部依存は増やさない（システムフレームワークのみ）。

前提: メニューバー常駐アプリ（`LSUIElement`）。メニューは `DeltaApp.swift` の `MenuContent`（`MenuBarExtra` 配下）。設定は `SettingsView` の `@AppStorage`。配布は GitHub Releases（タグ `vX.Y.Z`、CI 自動リリース）。リポジトリ `capybara-translation/delta`。

## 背景・動機

未公証・未署名配布のため Sparkle 等の自動更新は摩擦が大きい（署名・自己置換・quarantine）。一方「新版が出たことに気づけない」問題は残る。**更新はせず、検知して Releases ページへ誘導する**軽量な仕組みなら、依存ゼロ・数十行で実現でき、上記の難所を回避できる。

## ゴール

- 起動時（設定 ON 時）に最新リリースを確認し、現バージョンより新しければメニューに `Update available (vX.Y.Z)` を出す。クリックで Releases を開く。
- メニューの「Check for Updates…」でいつでも手動確認でき、結果をアラート表示する。
- Settings に「Check for updates on launch」トグル（既定 ON）。

**成功基準**:
- 現バージョンより新しいタグが Releases にあるとき、メニューに項目が出て、クリックで既定ブラウザに Releases が開く。
- 手動チェックで「新版あり／最新／失敗」を `NSAlert` で明示。
- 起動時チェックはトグル OFF で行われない。通信失敗時は起動時無音・手動はエラーアラート。
- 既存機能・既存テストは維持。外部依存を追加しない。

## 主要な設計判断

| 項目 | 決定 | 理由 |
|---|---|---|
| 範囲 | 通知＋ページを開くのみ（自動更新なし） | 未署名配布の難所を回避しつつ気づきを提供。 |
| 通知方式 | メニュー内項目（起動時）＋ `NSAlert`（手動） | メニューバーアプリと相性最良・通知許可不要。 |
| 取得先 | `GET https://api.github.com/repos/capybara-translation/delta/releases/latest` | 安定版のみ（draft/prerelease 除外）。`tag_name` を使用。 |
| 比較 | `v` 除去 → `String.compare(options: .numeric)` | `1.10.0 > 1.9.0` を正しく判定。semver ライブラリ不要。 |
| 開く URL | `https://github.com/capybara-translation/delta/releases/latest` | 常に最新へリダイレクト。特定タグ URL 生成が不要。 |
| 起動時トグル | `@AppStorage("checkForUpdatesOnLaunch")` 既定 true | 通信するので OFF 可能に。手動チェックは設定に依らず常時可。 |

## コンポーネント（すべてシステムフレームワークのみ）

| ファイル | 役割 |
|---|---|
| `Delta/Update/GitHubRelease.swift`（新規） | `struct GitHubRelease: Decodable { let tagName: String }`（`CodingKeys: tag_name`）。純粋なデコード対象。 |
| `Delta/Update/VersionComparator.swift`（新規・純粋） | `static func isNewer(latestTag: String, currentVersion: String) -> Bool`。両者の先頭 `v`/`V` を除去し `.compare(options: .numeric) == .orderedDescending`。 |
| `Delta/Update/UpdateChecker.swift`（新規・`@MainActor @Observable final class`） | シングルトン。`URLSession` 取得→デコード→比較。`latestVersion: String?`、`isUpdateAvailable: Bool`。`checkOnLaunch()`（設定 ON 時のみ・静か）/`checkManually()`（`NSAlert`）/`openReleasesPage()`。定数 `releasesURL` / API URL / repo。 |
| `Delta/DeltaApp.swift`（修正） | `MenuContent` に更新項目（更新ありのとき上部）と「Check for Updates…」を追加。`AppDelegate.applicationDidFinishLaunching` で `UpdateChecker.shared.checkOnLaunch()`。 |
| `Delta/Views/SettingsView.swift`（修正） | `@AppStorage("checkForUpdatesOnLaunch") var = true` のトグル「Check for updates on launch」。 |
| `DeltaTests/VersionComparatorTests.swift` / `DeltaTests/GitHubReleaseTests.swift`（新規） | 純粋ロジックの単体テスト。 |

`project.yml` 無変更（新規 `.swift` は `Delta/` 配下で自動取り込み。`xcodegen generate` は新規ファイル追加後に実行）。

### GitHubRelease（新規）

```swift
struct GitHubRelease: Decodable {
    let tagName: String
    enum CodingKeys: String, CodingKey { case tagName = "tag_name" }
}
```

### VersionComparator（新規・純粋）

```swift
enum VersionComparator {
    /// True if latestTag represents a strictly newer version than currentVersion.
    /// Leading "v"/"V" is stripped; comparison is numeric (so 1.10.0 > 1.9.0).
    static func isNewer(latestTag: String, currentVersion: String) -> Bool {
        let latest = strip(latestTag)
        let current = strip(currentVersion)
        return latest.compare(current, options: .numeric) == .orderedDescending
    }
    private static func strip(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        if let f = t.first, f == "v" || f == "V" { t.removeFirst() }
        return t
    }
}
```

### UpdateChecker（新規・@MainActor @Observable）

- 定数:
  - `apiURL = URL(string: "https://api.github.com/repos/capybara-translation/delta/releases/latest")!`
  - `releasesURL = URL(string: "https://github.com/capybara-translation/delta/releases/latest")!`
- 状態: `private(set) var latestVersion: String?`、`private(set) var isUpdateAvailable = false`。
- `currentVersion`: `Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""`。
- `checkOnLaunch()`: `@AppStorage`/`UserDefaults` の `checkForUpdatesOnLaunch`（未設定は true）が true のときのみ `fetchAndCompare()`。失敗は無音（状態を更新しない）。
- `checkManually()`: 常に `fetchAndCompare()` を実行し、結果で `NSAlert`:
  - 新版: informative「A new version (\(latest)) is available.」＋ ["Open Releases", "Later"]。Open で `openReleasesPage()`。
  - 最新: 「You're up to date (\(currentVersion)).」＋ ["OK"]。
  - 失敗: 「Couldn't check for updates.」＋ ["OK"]。
- `fetchAndCompare()` （`async` 内部、`throws`）: `URLSession.shared.data(for:)` で取得。`URLRequest` に **`User-Agent`（例 "Delta-Diff"）** と `Accept: application/vnd.github+json` を付与（GitHub は UA 無しだと 403）。HTTP ステータス 200 を確認、`GitHubRelease` にデコード、`VersionComparator.isNewer` で判定。成功時 `latestVersion`・`isUpdateAvailable` を更新。
- `openReleasesPage()`: `NSWorkspace.shared.open(releasesURL)`。

### DeltaApp / MenuContent（修正）

- `MenuContent` は `UpdateChecker.shared` を観測（`@State private var updateChecker = UpdateChecker.shared`、`@Observable` なので body で参照すれば更新に追従）。
- レイアウト:
  - `if updateChecker.isUpdateAvailable, let v = updateChecker.latestVersion { Button("Update available (\(v))") { updateChecker.openReleasesPage() }; Divider() }`（メニュー上部）。
  - 既存 "Open Delta Diff…" / "Settings…"。
  - 追加 `Button("Check for Updates…") { updateChecker.checkManually() }`（Settings の近く）。
  - 既存 Divider / "Quit Delta Diff"。
- `AppDelegate.applicationDidFinishLaunching`: `UpdateChecker.shared.checkOnLaunch()` を追加（既存の `clearTextIfNeeded()` / `HotKeyController.shared.start()` と並べる）。

### SettingsView（修正）

- `@AppStorage("checkForUpdatesOnLaunch") private var checkForUpdatesOnLaunch = true`。
- `Toggle("Check for updates on launch", isOn: $checkForUpdatesOnLaunch)` を Form に追加（既存トグル群の並び）。

## データフロー

```
起動: AppDelegate → checkOnLaunch()（設定ON時）
        → URLSession(api releases/latest) → GitHubRelease.tagName
        → VersionComparator.isNewer(latest, current)? → isUpdateAvailable=true, latestVersion=tag
        → MenuContent が "Update available (vX.Y.Z)" を表示
手動: メニュー "Check for Updates…" → checkManually() → 同取得
        → NSAlert（新版/最新/失敗）→ Open Releases で NSWorkspace.open(releasesURL)
項目クリック: openReleasesPage() → NSWorkspace.open(releasesURL)
```

## エラー処理・エッジケース

- **通信失敗/オフライン/レート超過(403,未認証60/時)**: 起動時は状態更新せず無音。手動は「Couldn't check for updates.」。
- **HTTP 非200 / デコード失敗 / 不正 JSON**: 上と同様（失敗扱い）。
- **currentVersion 空**（Info.plist 欠落の想定外時）: `isNewer` は空文字比較で latest が非空なら true になりうるが、通常発生しない。実害は「更新ありと出る」程度で安全側。
- **同値/ダウングレード**: `isNewer` false → 項目を出さない。
- **設定 OFF**: 起動時チェックしない。手動は可能。

## テスト方針

純粋ロジックを単体テスト（`import Testing`）:
- `VersionComparatorTests`:
  - `isNewer("v1.3.1", "1.3.0") == true`、`isNewer("v1.10.0", "1.9.0") == true`（数値比較）。
  - `isNewer("v1.3.0", "1.3.0") == false`（同値）、`isNewer("v1.2.0", "1.3.0") == false`（古い）。
  - `v` 有無の両対応（`isNewer("1.3.1", "v1.3.0") == true`）。
- `GitHubReleaseTests`:
  - サンプル JSON `{"tag_name":"v1.3.1","name":"v1.3.1"}` を `JSONDecoder` でデコード → `tagName == "v1.3.1"`。

副作用（`URLSession` 実通信・`NSAlert`・`NSWorkspace`・メニュー表示・`@AppStorage`）は UI/ネットワーク依存のため**手動確認**:
- 現バージョンを一時的に下げた状態で起動 → メニューに `Update available (…)` → クリックで Releases が開く。
- 手動「Check for Updates…」で 3 系統（新版/最新/失敗＝機内モード等）のアラート。
- Settings のトグル OFF で起動時チェックが走らない（新版があっても項目が出ない）。手動は動く。

## 非対象（YAGNI）

- 実際のダウンロード/インストール（自動更新）。
- 定期バックグラウンドチェック（今回は起動時＋手動のみ）。
- ネイティブ通知（`UNUserNotificationCenter`）・アイコンバッジ。
- pre-release/draft の扱い（`/releases/latest` が安定版のみ返すため対象外）。
- 「Later」で一定期間再通知しないスヌーズ。
