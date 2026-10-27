#!/bin/sh
# Builds NxLauncher.app (release, Apple silicon) into build/: swift build, then the bundle, its icon, the nxnative it ships
# (a git archive of the vendor/nxnative submodule) and an ad-hoc signature.
# Works with the Command Line Tools alone. Their newest SDK may declare SwiftUI's @State as a macro whose plugin ships only with Xcode;
# without Xcode the build then uses a macOS 26 SDK from the Command Line Tools.
# Usage: scripts/make_app.sh [--sign "<identity>"]
set -eu
cd "$(dirname "$0")/.."

SIGN=-
if [ "${1:-}" = "--sign" ]; then SIGN=$2; fi

if [ ! -e vendor/nxnative/scripts/build_ipa_from_nsp.py ]; then
  echo "vendor/nxnative is empty: run git submodule update --init" >&2; exit 1
fi

if ! xcode-select -p | grep -q '\.app/'; then
  SDK=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.*.sdk 2>/dev/null | sort -V | tail -1 || true)
  [ -n "$SDK" ] && export SDKROOT="$SDK"
fi

swift build -c release --arch arm64
BIN=$(swift build -c release --arch arm64 --show-bin-path)/NxLauncher

APP=build/NxLauncher.app
VERSION=$(git describe --tags --always 2>/dev/null || echo 0.1)
rm -rf "$APP.partial"
mkdir -p "$APP.partial/Contents/MacOS" "$APP.partial/Contents/Resources"
cp "$BIN" "$APP.partial/Contents/MacOS/NxLauncher"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
swift scripts/make_icon.swift "$TMP/icon.png"
mkdir "$TMP/AppIcon.iconset"
for n in 16 32 128 256 512; do
  sips -s format png -z $n $n "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${n}x${n}.png" >/dev/null
  sips -s format png -z $((n * 2)) $((n * 2)) "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${n}x${n}@2x.png" >/dev/null
done
iconutil -c icns "$TMP/AppIcon.iconset" -o "$APP.partial/Contents/Resources/AppIcon.icns"

# nxnative, as committed in the submodule: the launcher unpacks it on first launch (Engine.swift).
git -C vendor/nxnative archive --format=tar HEAD | gzip -9 > "$APP.partial/Contents/Resources/nxnative.tar.gz"
git -C vendor/nxnative rev-parse HEAD > "$APP.partial/Contents/Resources/nxnative.version"

cat > "$APP.partial/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>nxnative Launcher</string>
  <key>CFBundleDisplayName</key><string>nxnative Launcher</string>
  <key>CFBundleIdentifier</key><string>org.nxnative-launcher.app</string>
  <key>CFBundleExecutable</key><string>NxLauncher</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

codesign --force --sign "$SIGN" "$APP.partial" >/dev/null
rm -rf "$APP"
mv "$APP.partial" "$APP"
echo "built $APP"
