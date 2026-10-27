#!/bin/sh
# Runs the tests. `swift test` builds the app target too, so without Xcode it uses the same macOS 26 SDK as make_app.sh;
# with that SDK the Command Line Tools find Swift Testing's macro plugin only when told where it is.
set -eu
cd "$(dirname "$0")/.."
if ! xcode-select -p | grep -q '\.app/'; then
  SDK=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.*.sdk 2>/dev/null | sort -V | tail -1 || true)
  if [ -n "$SDK" ]; then
    export SDKROOT="$SDK"
    exec swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing "$@"
  fi
fi
exec swift test "$@"
