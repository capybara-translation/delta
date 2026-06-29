# Delta Diff グローバルホットキーのカスタマイズ UI 設計 (2026-06-29)

Diff ウィンドウ表示/非表示トグルのグローバルホットキー（現状 `⌃⌥D` 固定）を、Settings から録音・変更・無効化できるようにする。

前提: メニューバー常駐アプリ（`LSUIElement: true`）。グローバルホットキーは `GlobalHotKey`（Carbon `RegisterEventHotKey`）で実装され、`AppDelegate.applicationDidFinishLaunching` で `⌃⌥D` 固定登録、インスタンスをライフタイム保持している。外部依存はゼロ（システムフレームワークのみ）。

## 背景・動機

ホットキーが `⌃⌥D` 固定のため、他アプリと競合する場合や好みに合わない場合に変更できない。System Settings 風の録音フィールドで自由に変更・無効化できるようにする。外部依存を増やさず、既存の Carbon 実装を再利用する。

## ゴール

Settings 画面で、(1) グローバルホットキーの ON/OFF、(2) キーの組み合わせの録音・変更、(3) デフォルト（`⌃⌥D`）へのリセットができる。設定は永続化され、次回起動時も反映される。

**成功基準**:
- Settings でホットキーを変更すると即時に新しい組み合わせが効く。
- ON/OFF トグルで即時に有効化/解除される（OFF 中はコンボが解放され、通常入力に戻る）。
- 修飾キー（`⌘`/`⌃`/`⌥` のいずれか）を最低 1 つ含まない組み合わせは弾く。
- 既に使用中などで登録に失敗した場合はエラー表示し、元の設定を維持（ロールバック）。
- 設定は再起動後も保持。既存機能・既存テストは維持。

## 主要な設計判断

| 項目 | 決定 | 理由 |
|---|---|---|
| 実装方式 | 自前実装（外部依存ゼロ維持） | 本アプリの「軽量・システムフレームワークのみ」方針を維持。Carbon を既に使用。 |
| 対象 | 単一ホットキー（トグルのみ） | 現状アクションは 1 つ。汎用化は YAGNI。 |
| 修飾キー必須 | `⌘`/`⌃`/`⌥` の最低 1 つを必須（`⇧` のみ・単独キーは不可） | 単独キーはグローバルだと通常入力を奪うため。 |
| 無効化 | Enable トグルで `RegisterEventHotKey` を解除/再登録 | OFF 中はコンボを解放。 |
| 永続化 | `UserDefaults`（keyCode / modifiers / enabled） | 既存の `@AppStorage` 流儀に合わせる。 |
| 失敗時 | エラー表示＋ロールバック | 競合（OSStatus 非 noErr）でユーザーを迷わせない。 |

## コンポーネント

| ファイル | 役割 |
|---|---|
| `Delta/HotKey/HotKeyConfig.swift`（新規） | 値型。`keyCode: UInt32`, `modifiers: UInt32`（Carbon フラグ）, `isEnabled: Bool`。デフォルト `⌃⌥D`・有効。バリデーション（修飾キー必須）。 |
| `Delta/HotKey/HotKeyStore.swift`（新規） | `UserDefaults` への読み書き。未設定時はデフォルトを返す。 |
| `Delta/HotKey/HotKeyController.swift`（新規, `@MainActor`） | 現在の `GlobalHotKey` を保持し `apply(_:)` で再登録/解除。登録成否を返す。シングルトン。 |
| `Delta/HotKey/GlobalHotKey.swift`（修正） | `RegisterEventHotKey` の `OSStatus` を表面化（`init?` で失敗時 nil）。 |
| `Delta/HotKey/KeyCodeFormatter.swift`（新規, 純粋関数） | keyCode → 文字、Carbon 修飾フラグ → `⌘⌥⌃⇧` シンボル、`NSEvent.ModifierFlags` ↔ Carbon フラグ変換。 |
| `Delta/Views/ShortcutRecorder.swift`（新規） | `NSViewRepresentable` ＋ 内部 `NSView`。クリックで録音、`keyDown`＋修飾キー取得、`Esc` でキャンセル。 |
| `Delta/Views/SettingsView.swift`（修正） | Enable トグル、Shortcut 録音フィールド、Reset ボタン、エラー表示を追加。 |
| `Delta/DeltaApp.swift`（修正） | `AppDelegate` の固定登録を `HotKeyController` 経由（起動時に保存設定を適用）に置換。 |

`project.yml` は無変更（新規 `.swift` は `Delta/` 配下で自動取り込み）。

### HotKeyConfig（新規）

```swift
struct HotKeyConfig: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32      // Carbon: cmdKey | optionKey | controlKey | shiftKey
    var isEnabled: Bool

    static let `default` = HotKeyConfig(keyCode: UInt32(kVK_ANSI_D),
                                        modifiers: UInt32(controlKey | optionKey),
                                        isEnabled: true)

    /// 修飾キー（cmd/ctrl/opt のいずれか）を最低 1 つ含むか。
    var hasRequiredModifier: Bool {
        modifiers & UInt32(cmdKey | controlKey | optionKey) != 0
    }

    var displayString: String { KeyCodeFormatter.string(keyCode: keyCode, modifiers: modifiers) }
}
```

### HotKeyStore（新規）

- キー: `"hotKeyKeyCode"`, `"hotKeyModifiers"`, `"hotKeyEnabled"`。
- `load() -> HotKeyConfig`: いずれか欠如なら `.default`。`enabled` は未設定時 true。
- `save(_ config: HotKeyConfig)`。

### HotKeyController（新規, @MainActor シングルトン）

- `private(set) var config: HotKeyConfig`（起動時に `HotKeyStore.load()`）。
- `start()`: 起動時呼び出し。`isEnabled` なら登録。
- `apply(_ new: HotKeyConfig) -> Bool`: 既存 `GlobalHotKey` を破棄し、`isEnabled` なら新コンボで `GlobalHotKey(...)` 生成。登録成功（または無効化）なら `config` 更新＋`HotKeyStore.save`＋`true`。失敗なら旧 `GlobalHotKey` を復帰し `false`。
- ハンドラは常に `DiffWindowManager.shared.toggle()`。

### GlobalHotKey（修正）

- `init?(keyCode:modifiers:handler:)`: `RegisterEventHotKey` の戻り値が `noErr` でなければ後始末して `nil` を返す。`InstallEventHandler` も同様にチェック。
- 既存の `deinit` 解除はそのまま。

### KeyCodeFormatter（新規, 純粋関数）

- `string(keyCode:modifiers:) -> String`: 修飾シンボル（`⌃⌥⇧⌘` の順）＋キー文字。
- keyCode → 文字: 主要キー（英数字・記号・F1–F12・矢印・space/return/tab/esc/delete 等）のマップ。未知は `"key \(keyCode)"` 等のフォールバック。
- `carbonFlags(from: NSEvent.ModifierFlags) -> UInt32` と逆変換。録音時の `NSEvent` フラグを Carbon フラグへ。

### ShortcutRecorder（新規）

- 内部 `NSView`（`acceptsFirstResponder = true`）。クリックで first responder 化＝録音状態。
- `keyDown`: `event.keyCode` と `event.modifierFlags`（`.deviceIndependentFlagsMask`）取得。
  - `Esc`: 録音キャンセル（現状維持）。
  - 修飾キー必須を満たさなければ無視して録音継続（軽くフラッシュ等で示唆、任意）。
  - 満たせば `onCapture(keyCode, carbonModifiers)` を呼び first responder を降りる。
- 表示: 録音中は "Type shortcut…"、非録音時は `config.displayString`。
- `NSViewRepresentable` でラップし `@Binding`/コールバックで SwiftUI と接続。

### SettingsView（修正）

- 既存 `Form` に追記:
  - `Toggle("Enable global hotkey", isOn:)` — OFF で `controller.apply(config.isEnabled=false)`。
  - `LabeledContent("Shortcut")` に `ShortcutRecorder`（`isEnabled=false` 時はグレーアウト）。
  - `Button("Reset to Default")` — `⌃⌥D` を `apply`。
  - 失敗時のエラーテキスト（`@State var errorMessage`）。
- 変更フロー: 録音/トグル/リセット → `HotKeyController.apply` → 成功で UI 反映、失敗で `errorMessage` セット＋元の表示を維持。

### DeltaApp / AppDelegate（修正）

- `applicationDidFinishLaunching` の `GlobalHotKey(...)` 直接生成を削除し、`HotKeyController.shared.start()` を呼ぶ。
- `HotKeyController` がインスタンスを保持（ライフタイム維持）。

## データフロー

```
起動: AppDelegate.start() → HotKeyController.load → (enabled) GlobalHotKey 登録
変更: SettingsView 録音/トグル/Reset → HotKeyController.apply(config)
        ├ 成功: HotKeyStore.save + config 更新 + UI 反映
        └ 失敗: 旧 GlobalHotKey 復帰 + errorMessage 表示（保存しない）
発火: グローバルキー押下 → GlobalHotKey.handler → DiffWindowManager.shared.toggle()
```

## エラー処理・エッジケース

- **登録失敗（競合）**: `apply` が `false` を返し、旧設定を維持。Settings にエラー表示。
- **修飾キー不足**: 録音段階で弾く（保存に到達しない）。
- **無効化中の変更**: Enable が OFF の間に録音した場合は `config` を更新・保存するが登録はしない（ON にした時点で登録）。
- **デフォルト未設定の初回起動**: `HotKeyStore.load()` が `.default` を返し、従来どおり `⌃⌥D` 有効。

## テスト方針

純粋ロジックを単体テスト（`Testing` フレームワーク, `import Testing`）:
- `HotKeyConfig`: デフォルト値、`hasRequiredModifier`（cmd/ctrl/opt あり→true、shift のみ/無し→false）。
- `HotKeyStore`: 保存→読込の往復、未設定時に `.default`。
- `KeyCodeFormatter`: 修飾フラグ→シンボル順（`⌃⌥⇧⌘`）、主要 keyCode→文字、`NSEvent.ModifierFlags` ↔ Carbon フラグ変換の往復。

OS/UI 依存（`RegisterEventHotKey` の実登録、`ShortcutRecorder` の `keyDown`）はロジックを純粋関数へ切り出した上で**手動確認**:
- 既定 `⌃⌥D` でトグル動作。
- 別コンボに変更→即時反映。
- OFF→解除、ON→再登録。
- Reset→`⌃⌥D` 復帰。
- 再起動後も設定保持。

## 非対象（YAGNI）

- 複数アクション/複数ホットキーの登録。
- アプリ内ローカルショートカット（Diff ウィンドウ内のキー操作）の変更。
- 競合する他アプリの特定・表示（「使用中」一般メッセージのみ）。
