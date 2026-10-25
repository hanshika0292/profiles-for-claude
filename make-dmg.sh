#!/bin/bash
# Builds the app and packages it as a drag-to-Applications DMG for sharing.
# Any arguments (e.g. --install) are passed through to build.sh.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh "$@"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
DMG="build/Claude-Manager-$VERSION.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp -R "build/Claude Manager.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
# Optional notes for testers; added to the DMG only if the file exists.
if [[ -f "dist/Read Me First.txt" ]]; then cp "dist/Read Me First.txt" "$STAGE/"; fi

rm -f "$DMG"
hdiutil create -volname "Claude Manager $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
echo "Created $DMG"
