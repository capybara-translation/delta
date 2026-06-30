# Delta Diff

[![CI](https://github.com/capybara-translation/delta/actions/workflows/ci.yml/badge.svg)](https://github.com/capybara-translation/delta/actions/workflows/ci.yml)

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
- **Global hotkey** — show or hide the diff window from anywhere with a
  system-wide shortcut (`⌃⌥D` by default, customizable in Settings).

## Install

1. Download `Delta-Diff.zip` from the [latest release](../../releases/latest)
   and unzip it.

2. Move `Delta Diff.app` to `/Applications`.

3. The app is distributed for free and is **not notarized**, so on first launch
   macOS Gatekeeper blocks it. Clear the quarantine attribute once:

   ```bash
   xattr -dr com.apple.quarantine "/Applications/Delta Diff.app"
   ```

4. Launch the app (double-click `Delta Diff.app`, or run
   `open "/Applications/Delta Diff.app"`). A Delta (δ) icon appears in the menu
   bar.

5. Click the Delta (δ) icon in the menu bar and choose **Open Delta Diff…**. The
   diff window opens, ready for you to paste and compare two pieces of text.

To build it yourself instead, see the developer instructions below.

## Settings

Open settings from the menu bar: click the Delta (δ) icon and choose
**Settings…**. All settings are remembered across launches.

- **Keep text between launches** — when on, the two input boxes keep their text
  after you quit and reopen the app; when off, each launch starts empty.
- **Launch at login** — start Delta automatically when you log in.
- **Global hotkey** — a system-wide shortcut that shows/hides the diff window
  from any app. It is on by default, bound to `⌃⌥D`.
  - **Enable global hotkey** turns it on or off.
  - **Shortcut** records a new combination: click the field, then press the keys
    you want. The combination must include at least one of `⌘` / `⌃` / `⌥`;
    press `Esc` to cancel.
  - **Reset to Default** restores `⌃⌥D`.
- **Version** shows the installed app version.

## Requirements (to build from source)

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

Choose "Open Delta Diff…" from the Delta (δ) icon in the menu bar to open the
window.

## Test

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Delta.xcodeproj -scheme Delta \
  -destination 'platform=macOS' test
```

## License

[MIT](LICENSE) © 2026 capybara-translation
