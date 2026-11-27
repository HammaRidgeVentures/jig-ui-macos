#!/usr/bin/env bash
# bundle.sh — build "Jig Screen.app" into build/. It needs the Command Line Tools only, not Xcode.
#
#   bash scripts/bundle.sh             build it
#   bash scripts/bundle.sh --install   build it, copy it to /Applications, and open it
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

version=$(cat VERSION)

swift build -c release --product JigScreen 2>&1 | grep -v "search path" >&2 || true
bin=$(swift build -c release --show-bin-path)/JigScreen
[ -x "$bin" ] || { echo "The build made no program at $bin" >&2; exit 1; }

# Start from an empty bundle, so a file from an older build never ships.
rm -rf "build/Jig Screen.app"
mkdir -p "build/Jig Screen.app/Contents/MacOS" "build/Jig Screen.app/Contents/Resources"
cp "$bin" "build/Jig Screen.app/Contents/MacOS/JigScreen"
cp mock/status.json "build/Jig Screen.app/Contents/Resources/mock-status.json"
sed "s/@VERSION@/$version/g" scripts/Info.plist >"build/Jig Screen.app/Contents/Info.plist"

# An ad-hoc signature: enough to run on this Mac and to launch at login. It is not notarized.
codesign --force --sign - "build/Jig Screen.app" >&2

if [ "${1:-}" = "--install" ]; then
  # Quit the running copy, and wait until it is gone: `open` fails on an app that is still quitting.
  pkill -x JigScreen 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x JigScreen >/dev/null || break; sleep 0.3; done
  # ditto copies over an older install in place.
  ditto "build/Jig Screen.app" "/Applications/Jig Screen.app"
  open "/Applications/Jig Screen.app"
  echo "installed /Applications/Jig Screen.app"
else
  echo "built build/Jig Screen.app"
fi
