# Xeditor

A native macOS text editor with an Apple-style interface, built with SwiftUI/AppKit and the
Scintilla editing engine. Xeditor is a macOS-first reimagining of the feature set of
[Notepad--](https://github.com/cxasm/notepad--) (GPLv3).

## Status

**M1 — app skeleton (in progress).** The app hosts the upstream Scintilla Cocoa view inside
SwiftUI and supports opening, editing, saving, syntax highlighting, system light/dark mode,
multiple documents with a custom tab strip, per-document dirty state, close confirmation,
recent files and session restore.

M0 validation results (Debug build, `-O0` Scintilla, Apple silicon):

| File | Open time | Peak RSS |
|---|---|---|
| 10 MB | 3.6 s | 124 MB |
| 50 MB | 4.2 s | 329 MB |
| 500 MB | 12.5 s | 1.75 GB |

The lexer styles only the visible range on paint; there is no eager whole-document
colourise on open. Release builds and chunked file loading are expected to improve both
numbers. Chinese text renders correctly; IME input still needs a manual pass.

## Architecture

```
Xeditor/
├─ Xeditor/App/       SwiftUI app shell, commands, tab strip, status bar
├─ Xeditor/Core/      Document model, document store, language presets
├─ Xeditor/Editor/    Objective-C++ bridge to ScintillaView
├─ scripts/           bootstrap.sh (submodules + XcodeGen)
└─ ThirdParty/
   ├─ scintilla/      Scintilla 5.x (editor core + native Cocoa view)
   └─ lexilla/        Lexilla 5.x (syntax-highlighting lexers)
```

The editor is **not** QScintilla. Xeditor links upstream Scintilla's Cocoa/AppKit view
(`cocoa/ScintillaView.mm`) and Lexilla's lexers statically.

## Requirements

- macOS 14 or later
- Xcode 16 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Scintilla and Lexilla sources in `ThirdParty/`

## Build

```sh
git submodule update --init --recursive   # Scintilla + Lexilla
make bootstrap   # fetch submodules and generate Xeditor.xcodeproj
make build       # build the Debug app
make run         # launch it
```

Launch with `Xeditor.app/Contents/MacOS/Xeditor --dark <file>` (or `--light`) to force a
theme while testing.

## Features

- **Apple-native UI**: Unified macOS toolbar, fluid tab bar with drag-to-reorder, native menus, and dark/light mode following system settings.
- **Editing Core**: Upstream Scintilla Cocoa engine with static Lexilla syntax highlighting for 20+ programming languages.
- **Find & Replace**:
  - Inline Safari/Xcode-style Find Bar (`⌘F`) with match count and search options (Regex, Case Sensitive, Whole Word).
  - Advanced Find & Replace panel (`⌥⌘F`) with single replace and Replace All.
  - Previous (`⇧⌘G`) and Next (`⌘G`) navigation.
- **Encoding Detection & Switching**:
  - Automatic detection of UTF-8, UTF-8 BOM, UTF-16, GB18030 / GBK, and ISO Latin 1.
  - Status bar one-click encoding reload/switch menu.
- **Navigation & Positioning**:
  - Go to Line (`⌘L`) with input validation and instant jump.
  - Real-time cursor line/column indicators (`Ln X, Col Y`) in status bar.
- **Code Folding**:
  - Fold margin with fold icons, automatic folding, and fold toggling on click.
  - Shortcuts: Toggle Current (`⌥⌘O`), Fold All (`⌥⌘[`), Unfold All (`⌥⌘]`).
- **Bookmarks**:
  - Bookmark margin with visual indicator badges, click-to-toggle margin.
  - Shortcuts: Toggle Bookmark (`⌘F2`), Next Bookmark (`F2`), Previous Bookmark (`⇧F2`), Clear All.
- **Line & Text Operations**:
  - Duplicate Line (`⌘D`), Delete Line (`⇧⌘K`), Move Line Up (`⌥↑`), Move Line Down (`⌥↓`), Join Lines (`⌘J`).
  - Toggle Line Comment (`⌘/`) according to current language comment syntax.
  - Make Upper Case (`⇧⌘U`), Make Lower Case (`⌘U`), Sort Lines (Ascending / Descending), Trim Trailing Whitespace.
- **Intelligent Indentation & Brackets**:
  - Auto-indent upon pressing Enter.
  - Real-time bracket matching and bad-match warnings for `()`, `[]`, `{}`.
  - Adaptive line number margin width according to total line count.
- **Preferences (`⌘,`)**:
  - Customizable monospaced font family and fractional font size (`⌘+`, `⌘-`, `⌘0`).
  - Tab width configuration, tab vs. spaces toggle, auto-indent toggle.
  - Word wrap toggle, show whitespace characters, and indentation guide lines.

GPLv3. See `LICENSE`. Scintilla and Lexilla are distributed under their own permissive
licenses (see `ThirdParty/scintilla/License.txt` and `ThirdParty/lexilla/License.txt`).
