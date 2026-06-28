# Delta Diff

A lightweight menu-bar diff tool for macOS. Open a small window from the menu
bar, paste two pieces of text, and see a color-coded difference — without
launching a full editor or reaching for the command line.

Delta is built for spotting fine character-level differences, including
encoding differences (e.g. NFC vs NFD) that look identical on screen.

## Features

- **Menu-bar resident** — lives in the menu bar (no Dock icon); open the diff
  window on demand.
- **Side-by-side diff** — left/right (or top/bottom) panes with row alignment,
  switchable and remembered between launches.
- **Intraline highlighting** — within a changed line, only the differing
  characters are highlighted (works for Japanese, emoji, and combining marks).
- **Encoding-aware** — comparison is Unicode-scalar based, so canonically
  equivalent but differently encoded text (NFC vs NFD) is reported as a
  difference.
- **Code-point inspector** — the Unicode code points of the selected character
  (or the character before the caret) are shown beneath each input box.
- **Keyboard-friendly** — `Tab` / `Shift+Tab` move focus between the two input
  boxes, `Ctrl+Tab` inserts a literal tab, and `Cmd+Return` runs the compare.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode (at `/Applications/Xcode.app`)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Setup / Build

This repository does not track the `.xcodeproj`; it is generated from
`project.yml`.

```bash
xcodegen generate
```

If `xcode-select` points at the Command Line Tools rather than Xcode, prefix
build commands with `DEVELOPER_DIR`:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Delta.xcodeproj -scheme Delta -configuration Debug \
  -derivedDataPath build build
```

## Run

```bash
open build/Build/Products/Debug/Delta.app
```

Choose "Open Delta Diff" from the document icon (`doc.on.doc`, an SF Symbol)
in the menu bar to open the window.

## Test

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Delta.xcodeproj -scheme Delta \
  -destination 'platform=macOS' test
```

## License

[MIT](LICENSE) © 2026 capybara-translation
