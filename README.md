# Delta

macOS の常駐型 GUI Diff ツール。メニューバーから小窓を開き、2つのテキストの差分をカラー表示する。

## 必要環境

- macOS 14 (Sonoma) 以降
- Xcode（`/Applications/Xcode.app`）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）

## セットアップ / ビルド

このリポジトリは `.xcodeproj` を管理していません。`project.yml` から生成します。

```bash
xcodegen generate
```

`xcode-select` が CommandLineTools を指している環境では `DEVELOPER_DIR` を前置してビルドします。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Delta.xcodeproj -scheme Delta -configuration Debug \
  -derivedDataPath build build
```

## 実行

```bash
open build/Build/Products/Debug/Delta.app
```

メニューバーの δ アイコン（`doc.on.doc`）から "Open Diff Window" を選ぶとウィンドウが開く。

## テスト

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Delta.xcodeproj -scheme Delta \
  -destination 'platform=macOS' test
```
