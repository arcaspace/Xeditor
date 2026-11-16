#!/bin/bash
# Package a built Xeditor.app into a compressed, drag-to-install DMG.
# Usage: make-dmg.sh <path-to-app> <output-dmg> <version>
set -euo pipefail

APP_PATH="${1:?usage: make-dmg.sh <app> <dmg> <version>}"
OUT_DMG="${2:?usage: make-dmg.sh <app> <dmg> <version>}"
VERSION="${3:?usage: make-dmg.sh <app> <dmg> <version>}"
VOLUME_NAME="Xeditor ${VERSION}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/xeditor-dmg.XXXXXX")"
DMG_RW="${STAGE}/Xeditor-rw.dmg"
MOUNT_POINT="${STAGE}/mnt"

cleanup() {
  if [ -d "${MOUNT_POINT}" ]; then
    hdiutil detach "${MOUNT_POINT}" -quiet >/dev/null 2>&1 || true
  fi
  rm -rf "${STAGE}"
}
trap cleanup EXIT

if [ ! -d "${APP_PATH}" ]; then
  echo "error: app not found at ${APP_PATH}" >&2
  exit 1
fi

# Layout shown to the user: the app next to an Applications shortcut.
LAYOUT="${STAGE}/layout"
mkdir -p "${LAYOUT}"
ditto "${APP_PATH}" "${LAYOUT}/Xeditor.app"
ln -s /Applications "${LAYOUT}/Applications"
if [ -f "${ROOT}/LICENSE" ]; then
  cp "${ROOT}/LICENSE" "${LAYOUT}/LICENSE"
fi

# Ad-hoc sign the staged bundle so it stays internally consistent after the
# copy (the Release build is intentionally unsigned for distribution).
codesign --force --deep --sign - "${LAYOUT}/Xeditor.app"

# Build a read-write image, then convert it so the result is compressed.
hdiutil create -quiet -volname "${VOLUME_NAME}" -srcfolder "${LAYOUT}" \
  -fs HFS+ -format UDRW -ov "${DMG_RW}"
mkdir -p "${MOUNT_POINT}"
hdiutil attach -quiet -nobrowse -mountpoint "${MOUNT_POINT}" "${DMG_RW}"

# Finder window with icon view is a nicety; ignore failures on headless runs.
osascript <<EOF >/dev/null 2>&1 || true
tell application "Finder"
  tell disk "${VOLUME_NAME}"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 160, 740, 540}
    set theViewOptions to icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 128
    close
  end tell
end tell
EOF

sync
hdiutil detach -quiet "${MOUNT_POINT}"
rmdir "${MOUNT_POINT}" 2>/dev/null || true

mkdir -p "$(dirname "${OUT_DMG}")"
rm -f "${OUT_DMG}"
hdiutil convert -quiet "${DMG_RW}" -format UDZO -imagekey zlib-level=9 -o "${OUT_DMG}"
echo "Created ${OUT_DMG}"
