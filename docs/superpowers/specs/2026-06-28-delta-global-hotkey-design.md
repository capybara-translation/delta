# Delta グローバルホットキー 設計 (2026-06-28)

どのアプリが最前面でも、グローバルホットキー ⌃⌥D で Diff ウィンドウをトグル表示する。

前提: メニューバー常駐アプリ。ウィンドウは AppKit 管理の `DiffWindowManager`（`Delta/Window/DiffWindowManager.swift`）。元設計メモ（`docs/Delta.md`）の推奨順 3 に相当。

## 背景・動機

メニューからウィンドウを開く操作を、どのアプリからでもワンキーで呼び出せるようにする。「ちょっとした差分確認」を素早く始めるための常駐型ツールの核となる導線。SwiftUI だけでは完結しない唯一の部分。

## ゴール

アプリ起動時にグローバルホットキー ⌃⌥D（Control+Option+D）を登録し、押下で Diff ウィンドウをトグル（前面表示↔隠す）する。

**成功基準**: 別アプリが最前面の状態で ⌃⌥D を押すと Delta のウィンドウが前面に出る。最前面のとき再度押すと隠れる。アクセシビリティ権限は要求しない。既存テストは緑のまま。

## 主要な設計判断

| 項目 | 決定 | 理由 |
|---|---|---|
| 登録方式 | Carbon `RegisterEventHotKey` | 外部依存ゼロを維持、App Store 向き、アクセシビリティ権限不要（登録型）。 |
| デフォルト組み合わせ | ⌃⌥D（`controlKey | optionKey` + `kVK_ANSI_D`） | Delta の D。macOS 標準ショートカットと衝突しにくい。 |
| 押下時の挙動 | トグル（key window なら隠す、それ以外は表示＋前面化） | 「呼び出しツール」として自然。 |
| カスタマイズ | 今回スコープ外。ただし `keyCode`/`modifiers` を引数化 | 後の「設定永続化」フェーズで設定 UI を足しやすくする。 |
| 配線 | `@NSApplicationDelegateAdaptor` の `AppDelegate` で登録・保持 | MenuBarExtra アプリに起動フックと保持先を用意する標準手段。 |

## コンポーネント

| ファイル | 役割 |
|---|---|
| `Delta/HotKey/GlobalHotKey.swift`（新規） | Carbon の薄いラッパ。登録・解除・発火コールバック。 |
| `Delta/Window/DiffWindowManager.swift`（修正） | `toggle()` を追加。 |
| `Delta/DeltaApp.swift`（修正） | `AppDelegate` を追加し、起動時に `GlobalHotKey` を生成・保持。 |

`DiffEngine`・`DiffWindowView`・各 View・`CodePointTextView` 等は無変更。

### GlobalHotKey（Carbon ラッパ）

```swift
import Carbon

final class GlobalHotKey {
    init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void)
    deinit  // UnregisterEventHotKey + RemoveEventHandler
}
```

動作:
- `init` で `InstallEventHandler`（`kEventClassKeyboard` / `kEventHotKeyPressed`）と `RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)`。
- C コールバックには `Unmanaged.passUnretained(self).toOpaque()` を userData として渡し、コールバック内で `Unmanaged<GlobalHotKey>.fromOpaque(...).takeUnretainedValue()` で自身を復元し `handler()` を呼ぶ。
- コールバックはアプリのイベントターゲット（メインスレッド）で発火する。
- `deinit` で `UnregisterEventHotKey` と `RemoveEventHandler` を呼び後始末する。
- インスタンスが解放されると登録も外れるため、呼び出し側が**強参照で保持**する必要がある。

### DiffWindowManager.toggle()

```swift
func toggle() {
    if let window, window.isVisible, window.isKeyWindow {
        window.orderOut(nil)
    } else {
        show()
    }
}
```
- 既存 `show()` はウィンドウ生成（初回）＋ `makeKeyAndOrderFront` ＋ `NSApplication.shared.activate()`。
- 最前面（key window）のときだけ隠し、それ以外（非表示・背面・別アプリ前面）は `show()` で前面に出す。

### DeltaApp（AppDelegate 配線）

```swift
@main
struct DeltaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene { /* 既存の MenuBarExtra */ }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: GlobalHotKey?
    func applicationDidFinishLaunching(_ notification: Notification) {
        hotKey = GlobalHotKey(
            keyCode: UInt32(kVK_ANSI_D),
            modifiers: UInt32(controlKey | optionKey)
        ) {
            DiffWindowManager.shared.toggle()
        }
    }
}
```
既存の `MenuBarExtra` Scene と「Open Diff Window」「Quit」メニューは変更しない。

## リスク

- **[MED] Carbon ↔ Swift ブリッジ**: イベントハンドラ署名・`Unmanaged` ポインタ・OSType 定数の取り回しを誤ると無反応になる。手動確認で検証。
- **[MED] 保持忘れ**: `GlobalHotKey` を保持しないと即座に登録解除される。`AppDelegate` のプロパティで保持。
- **[LOW] ホットキー衝突**: ⌃⌥D が他アプリと衝突する可能性。後で設定化して回避可能にする。
- **[LOW] 後始末**: アプリ生存期間＝プロセス生存期間だが、`deinit` で明示解除しておく。

## テスト・検証計画

Carbon のシステム統合が中心で、意味のある単体テストは作れない（モックは過剰）。**ビルド＋手動確認**で検証する。

手動確認:
- 別アプリを最前面にして ⌃⌥D → Delta ウィンドウが前面に出る
- 最前面の状態で再度 ⌃⌥D → 隠れる
- メニューの「Open Diff Window」、diff 実行、Tab 移動、コードポイント表示が引き続き動く

自動テスト:
- 既存39テストが緑のまま（リグレッションなし）であることを確認。新規の単体テストは追加しない（システム統合のため）。

## スコープ外

- ホットキーのカスタマイズ UI / 永続化（「設定永続化」フェーズ）
- 複数ホットキー、用途別ホットキー
- 履歴・設定画面
