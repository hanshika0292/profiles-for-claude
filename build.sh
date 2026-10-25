#!/bin/bash
# Builds build/Claude Manager.app with the Xcode command-line tools (no Xcode project needed).
# Universal (Intel + Apple Silicon) by default; ARCHS=x86_64 ./build.sh for a quicker local build.
# Pass --install to copy it into ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Claude Manager.app"
BIN="$APP/Contents/MacOS/ClaudeManager"
read -r -a ARCH_LIST <<< "${ARCHS:-x86_64 arm64}"
rm -rf "$APP" build/AppIcon.iconset build/ClaudeManager-*
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

pids=()
for arch in "${ARCH_LIST[@]}"; do
  swiftc -O -target "$arch-apple-macos13.0" -parse-as-library \
    -import-objc-header Sources/Bridging.h \
    -framework AppKit -framework SwiftUI \
    Sources/*.swift -o "build/ClaudeManager-$arch" &
  pids+=($!)
done
for pid in "${pids[@]}"; do wait "$pid"; done
lipo -create build/ClaudeManager-* -output "$BIN"
rm -f build/ClaudeManager-*

cp Info.plist "$APP/Contents/"
"$BIN" --render-app-icon build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf build/AppIcon.iconset
codesign --force --sign - "$APP" >/dev/null 2>&1
echo "Built $APP ($(lipo -archs "$BIN"))"

if [[ "${1:-}" == "--install" ]]; then
  DEST="$HOME/Applications/Claude Manager.app"
  if pgrep -xq ClaudeManager; then
    osascript -e 'tell application id "local.claudemanager.app" to quit' >/dev/null 2>&1 || true
    sleep 1
  fi
  rm -rf "$DEST"
  mkdir -p "$HOME/Applications"
  cp -R "$APP" "$DEST"
  echo "Installed to $DEST"
fi
