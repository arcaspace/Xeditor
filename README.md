# Xeditor

A fast, native text and code editor for macOS, built with AppKit and the Scintilla
editing engine. Xeditor keeps the interface quiet, starts in under a second, and
never silently changes a file's encoding.

**[Download](https://github.com/arcaspace/Xeditor/releases/latest)** ·
**[Website](https://arcaspace.github.io/Xeditor/)** ·
**[All releases](https://github.com/arcaspace/Xeditor/releases)**

## Features

- **Native AppKit interface** — unified toolbar, drag-to-reorder tabs, native menus,
  system light/dark appearance, file drops and session restore.
- **Scintilla editing core** — upstream Scintilla view with static Lexilla lexers for
  20+ languages, syntax highlighting, code folding, bracket matching, indentation
  guides, bookmarks and adaptive line-number margins.
- **Find and replace** — inline Find Bar (`⌘F`) plus a full Find window (`⌥⌘F`) with
  regex, case-sensitive and whole-word modes, Replace All, a jumpable results panel,
  colour marks, bookmarks for matches and Copy Matches.
- **Encoding-safe saving** — detects UTF-8, UTF-8 with BOM, UTF-16, GB18030/GBK and
  Latin-1, then writes back in the file's own encoding and BOM. If the text cannot be
  represented, Xeditor asks before falling back to UTF-8.
- **Developer tools** — MD5/SHA hashing, Base64/URL codec, structured-data formatting,
  JSON ⇄ YAML conversion and file comparison.
- **Five interface languages** — English, 简体中文, 繁體中文, 日本語 and 한국어,
  switchable at runtime without restarting.
- **Editing conveniences** — duplicate, delete, move and join lines; toggle comments;
  change case; sort lines; trim trailing whitespace; Go to Line (`⌘L`).
- **Preferences (`⌘,`)** — font family and size, tab width, tabs vs. spaces,
  auto-indent, word wrap, whitespace display and indentation guides.

## Requirements

- macOS 14 Sonoma or later
- Apple silicon or Intel Mac (the release DMG is universal)

## Install

Download `Xeditor-0.2.0.dmg` from [Releases](https://github.com/arcaspace/Xeditor/releases/latest),
open it, and drag **Xeditor** onto the **Applications** folder.

The app is ad-hoc signed and not notarized. If macOS blocks the first launch,
right-click the app in Finder → **Open**, or allow it in
**System Settings → Privacy & Security**.

## Build from source

Requirements: Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`), and initialized submodules.

```sh
git clone --recursive https://github.com/arcaspace/Xeditor.git
cd Xeditor
make bootstrap   # fetch Scintilla/Lexilla and generate Xeditor.xcodeproj
make build       # Debug build
make run         # launch the app
```

If the repository was cloned without `--recursive`:

```sh
git submodule update --init --recursive
```

Launch with `Xeditor.app/Contents/MacOS/Xeditor --dark <file>` (or `--light`) to
force a theme while testing.

## Release packaging

The marketing version and build number live in `project.yml`
(`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`). To produce a distributable image:

```sh
make release
```

This builds the Release configuration as a universal binary, ad-hoc signs the bundle
and writes `dist/Xeditor-<version>.dmg` with an Applications shortcut and the license.
`dist/` is ignored by git.

## Architecture

```
Xeditor/
├─ Xeditor/App/       AppKit shell: windows, menus, tabs, status bar, preferences, tools
├─ Xeditor/Core/      Document model, document store, search, encodings, structured data
├─ Xeditor/Editor/    Objective-C++ bridge to the Scintilla Cocoa view
├─ docs/              Bilingual product site (GitHub Pages)
├─ scripts/           bootstrap.sh, make-dmg.sh
└─ ThirdParty/
   ├─ scintilla/      Scintilla 5.x (editor core + native Cocoa view)
   └─ lexilla/        Lexilla 5.x (syntax-highlighting lexers)
```

`ThirdParty/scintilla` and `ThirdParty/lexilla` are git submodules pinned to specific
upstream commits; `.gitmodules` records them.

## License

GPLv3. See [LICENSE](LICENSE). Scintilla and Lexilla are distributed under their own
permissive licenses (see `ThirdParty/scintilla/License.txt` and
`ThirdParty/lexilla/License.txt`).
