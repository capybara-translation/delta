# Delta — 常駐型 GUI Diff ツール 設計メモ

macOS の常駐型 GUI Diff ツール。ホットキー or メニューバーから小さなウィンドウを呼び出し、2つのテキストを入力 → 実行で色付き diff を表示する。テキストエディタやコマンドラインツールを立ち上げるのが面倒な「ちょっとした文字の差分確認」を素早く済ませるためのツール。

## 技術スタック

- **言語 / UI**: Swift + SwiftUI
- **形態**: メニューバー常駐アプリ（`MenuBarExtra`）
- **プロジェクト形式**: Xcode プロジェクト
- 選定理由: 常駐型の軽量ツールに最適。ネイティブで軽く、見た目も macOS らしい。App Store 配布も視野に入れられる。（Tauri / Electron / Wails / Python も検討したが、ネイティブ感と軽さで Swift を選択）

## 命名

| 対象 | スタイル | 値 |
|---|---|---|
| アプリ表示名 | PascalCase | `Delta` |
| Xcode プロジェクト名・フォルダ | PascalCase | `Delta` |
| ターゲット名 | PascalCase | `Delta` |
| Bundle Identifier | 逆ドメイン・小文字 | `com.capybara.delta` |
| Git リポジトリ名 | ケバブケース（小文字） | `delta`（必要なら `delta-diff`） |

- 公開・配布を考えるなら、表示名は `Delta` のまま、リポジトリ名や内部識別子は `delta-diff` のように具体化しておくと検索性・安全性で有利。
- 型は PascalCase、変数・関数・プロパティは camelCase、ファイル名は中身の型に合わせ PascalCase。

## ディレクトリ構成

```
delta/                       ← Git リポジトリ（小文字 / ケバブ）
├── Delta.xcodeproj
├── Delta/                   ← ソース（PascalCase）
│   ├── DeltaApp.swift       ← @main、メニューバー常駐の起点
│   ├── Views/
│   │   ├── DiffWindowView.swift   ← メインウィンドウ
│   │   ├── DiffEditorView.swift   ← 左右テキスト入力
│   │   ├── DiffResultView.swift   ← カラー diff 表示
│   │   ├── HistoryView.swift      ← 履歴
│   │   └── SettingsView.swift     ← 設定
│   ├── Models/
│   │   ├── DiffEngine.swift       ← diff 計算
│   │   └── HistoryEntry.swift
│   ├── Store/
│   │   ├── HistoryStore.swift     ← 履歴管理（@Observable）
│   │   └── SettingsStore.swift    ← 設定（@AppStorage）
│   └── HotKey/
│       └── GlobalHotKey.swift     ← グローバルホットキー
├── README.md
└── .gitignore
```

## 機能要件

### コア機能
- メニューバーアイコン（δ）から小さなウィンドウを呼び出す
- グローバルホットキーでウィンドウをトグル表示
- 左右2つのテキスト入力ボックス
- 実行ボタン（⌘↵）で色付き diff を表示（追加=緑背景 / 削除=赤背景）
- word diff / line diff の切り替え

### 設定（永続化）
- **テキスト保持の挙動**: 「前回入力したテキストを残す」/「毎回クリアする」を設定で切り替え可能にする
- `@AppStorage`（UserDefaults ラッパー）で保存

### 履歴
- 実行履歴を **30件程度** 保持（上限つき）
- 各エントリ: id / timestamp / textA / textB /（任意で label メモ）
- `@Observable` な Store クラス + UserDefaults に JSON エンコードして保存
- 件数が増えたら SwiftData への移行も検討可

## 実装方針メモ

### メニューバー常駐
- SwiftUI の `MenuBarExtra` を使用（最近の macOS ターゲットならこれが最も簡潔）
- `Window("Diff", id: "diff-main")` を別 Scene として定義し、メニューやホットキーから表示

```swift
@main
struct DeltaApp: App {
    var body: some Scene {
        MenuBarExtra("Delta", systemImage: "doc.on.doc") {
            Button("Open Diff Window") { /* ウィンドウ表示 */ }
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .menuBarExtraStyle(.menu)

        Window("Diff", id: "diff-main") {
            DiffWindowView()
        }
    }
}
```

### グローバルホットキー
SwiftUI だけでは完結しない唯一の部分。選択肢:
- `Carbon` の `RegisterEventHotKey`（低レベルだが確実、定番）
- [`HotKey` ライブラリ](https://github.com/soffes/HotKey)（Swift 製ラッパー、簡単。SPM で追加可）

→ 抵抗がなければ `HotKey` ライブラリが圧倒的に楽。

### Diff 計算
- 行単位なら Swift 標準の `CollectionDifference` で十分

```swift
let diff = textB.split(separator: "\n")
    .difference(from: textA.split(separator: "\n"))
```

- 単語単位の細かい diff が欲しい場合は自前実装か `swift-diff` などのライブラリ

### 設定の永続化
```swift
@AppStorage("keepTextOnReopen") var keepText = true
```

## 開発の進め方（推奨順）

1. `MenuBarExtra` + ウィンドウ表示だけ動かす
2. テキスト入力 + diff 計算 + カラー表示
3. グローバルホットキー追加
4. 設定（テキスト保持 / クリア）
5. 履歴
6. UI の細かい調整

Xcode プロジェクトのテンプレート（Product Name = `Delta`）から新規作成して開始する。
