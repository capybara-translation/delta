# Delta Diff Launch at login 設計 (2026-06-29)

設定ウィンドウに「Launch at login」トグルを追加し、ログイン時の自動起動を切り替える。

前提: メニューバー常駐アプリ。設定は `SettingsView`（`Settings` シーン）。`SMAppService`（ServiceManagement, macOS 13+）を使う。

## 背景・動機

常駐ツールとして、ログイン時に自動起動できると便利。システム設定のログイン項目に手動追加する代わりに、アプリ内のトグルで切り替えられるようにする。

## ゴール

設定ウィンドウのトグルで `SMAppService.mainApp` を register/unregister し、ログイン時自動起動を切り替える。トグルは OS の登録状態を反映する。

**成功基準**: ON にすると次回ログイン/再起動で自動起動し、システム設定 > 一般 > ログイン項目に Delta Diff が現れる。OFF で自動起動しなくなる。既存テストは緑のまま。

## 主要な設計判断

| 項目 | 決定 | 理由 |
|---|---|---|
| API | `SMAppService.mainApp`（register/unregister/status） | macOS 13+ の標準・推奨 API（対象は 14）。 |
| 状態の真実の源 | `SMAppService.mainApp.status`（`@AppStorage` に保存しない） | OS の登録状態が正。アプリ側で二重管理しない。 |
| 失敗時 | トグルを実状態に戻すだけ（アラートなし） | シンプル。YAGNI。 |
| ロジック分離 | `LaunchAtLogin`（薄いラッパ） | View から `SMAppService` を切り離す。 |

## コンポーネント

| ファイル | 役割 |
|---|---|
| `Delta/Models/LaunchAtLogin.swift`（新規） | `SMAppService.mainApp` のラッパ。`isEnabled` / `setEnabled(_:)`。 |
| `Delta/Views/SettingsView.swift`（修正） | 「Launch at login」トグルを追加。 |

`DiffEngine`・各 View・`HistoryStore`・`HTMLExporter`・`DiffWindowManager`・`GlobalHotKey` 等は無変更。

### LaunchAtLogin

```swift
import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
```

### SettingsView（修正）

`Form` に既存 Toggle・Version 行に加えて「Launch at login」を追加:
```swift
@State private var launchAtLogin = LaunchAtLogin.isEnabled

Toggle("Launch at login", isOn: Binding(
    get: { launchAtLogin },
    set: { newValue in
        try? LaunchAtLogin.setEnabled(newValue)
        launchAtLogin = LaunchAtLogin.isEnabled   // reflect the real status (reverts on failure)
    }
))
```
`.onAppear { launchAtLogin = LaunchAtLogin.isEnabled }` でウィンドウ表示時に現状へ同期する。`@State` ミラーを用意し、操作（binding の set）でのみ register/unregister を呼ぶことで再入を避ける。失敗時は `setEnabled` が throw し、続く `launchAtLogin = LaunchAtLogin.isEnabled` で実状態（元の値）に戻る。

## リスク

- **[MED] 登録対象は実行中 .app のパス**: 開発版（`build/...`）で ON にするとそのパスが登録され、移動/削除で壊れる。実用上は `/Applications` 版で確認するのが望ましい。
- **[LOW] 承認待ち（`.requiresApproval`）**: 初回 ON 時に macOS が承認を促す場合があり、その間は `status != .enabled` のためトグルは OFF 表示になる（承認後に ON）。仕様として許容。
- **[LOW] API 可用性**: `SMAppService` は macOS 13+。対象 14 で問題なし。

## テスト・検証計画

`SMAppService` はシステム統合で意味ある単体テストが作れないため、**ビルド＋手動確認**で検証する。

手動確認:
- 設定で「Launch at login」ON → システム設定 > 一般 > ログイン項目に Delta Diff が出る → ログアウト/再ログイン（または再起動）で自動起動
- OFF → ログイン項目から消える → 自動起動しない
- 失敗時（例: 未署名の不安定なパス）にトグルが実状態へ戻る
- 既存の diff・履歴・設定・HTML エクスポート・Tab・⌃⌥D が動く

自動テスト:
- 既存56テストが緑のまま（リグレッションなし）。新規テストは追加しない（システム統合のため）。

## スコープ外

- 起動時にウィンドウを自動で開く挙動（メニューバー常駐のまま）
- ログイン項目の詳細設定（遅延起動等）
- `@AppStorage` での状態二重管理
