#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="MultiViewer by Brekke"
VOLNAME="MultiViewer by Brekke"
DMG_NAME="MultiViewer-by-Brekke.dmg"
STAGING="$ROOT/dist/dmg-staging"
DMG_PATH="$ROOT/dist/$DMG_NAME"

"$SCRIPT_DIR/build-app.sh" release

rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$ROOT/dist/$APP_NAME.app" "$STAGING/"
ln -sf /Applications "$STAGING/Applications"

rm -f "$DMG_PATH"
hdiutil create \
    -volname "$VOLNAME" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$STAGING"

echo "Created $DMG_PATH"
echo "Mount with: open \"$DMG_PATH\""
