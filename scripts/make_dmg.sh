#!/bin/sh
# Packs build/NxLauncher.app into build/NxLauncher-<version>.dmg: the app beside an Applications link, to drag it across.
# Builds the app first with make_app.sh, passing --sign on; with an identity the disk image is signed too.
# Finder lays out the window (icon size and places) when this script may control it; otherwise the image keeps Finder's default view.
# Usage: scripts/make_dmg.sh [--sign "<identity>"]
set -eu
cd "$(dirname "$0")/.."

scripts/make_app.sh "$@"

SIGN=
if [ "${1:-}" = "--sign" ]; then SIGN=$2; fi

APP=build/NxLauncher.app
VOLNAME="nxnative Launcher"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
DMG="build/NxLauncher-$VERSION.dmg"

TMP=$(mktemp -d)
DEV=
cleanup() {
  [ -n "$DEV" ] && hdiutil detach "$DEV" -quiet -force 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

mkdir "$TMP/stage"
ditto "$APP" "$TMP/stage/NxLauncher.app"
ln -s /Applications "$TMP/stage/Applications"

# A writable image first, so Finder can store the window layout in it, then the compressed one.
hdiutil create -quiet -volname "$VOLNAME" -srcfolder "$TMP/stage" -fs HFS+ -format UDRW -ov "$TMP/rw.dmg"
# Mounted where Finder sees it (under /Volumes), since Finder lays out only the volumes it shows.
LINE=$(hdiutil attach "$TMP/rw.dmg" -readwrite -noverify -noautoopen | grep Apple_HFS)
DEV=$(printf '%s' "$LINE" | cut -f1 | tr -d ' ')
MOUNT=$(printf '%s' "$LINE" | cut -f3)
DISK=$(basename "$MOUNT")

if ! osascript >/dev/null 2>&1 <<EOF
tell application "Finder"
  set d to disk "$DISK"
  open d
  set w to container window of d
  set current view of w to icon view
  set toolbar visible of w to false
  set statusbar visible of w to false
  set bounds of w to {200, 120, 740, 460}
  set o to icon view options of w
  set arrangement of o to not arranged
  set icon size of o to 128
  set position of item "NxLauncher.app" of d to {140, 150}
  set position of item "Applications" of d to {400, 150}
  update d without registering applications
  delay 1
  close w
end tell
EOF
then
  echo "Finder did not lay out the window (allow your terminal to control Finder in Privacy & Security → Automation); keeping the default view" >&2
fi

rm -rf "$MOUNT/.fseventsd"
sync
hdiutil detach "$DEV" -quiet
DEV=
rm -f "$DMG"
hdiutil convert -quiet "$TMP/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG"
[ -n "$SIGN" ] && codesign --force --sign "$SIGN" "$DMG" >/dev/null
echo "built $DMG"
