#!/bin/bash
set -euo pipefail

# Packages build/zWhisper.app into a branded drag-to-Applications .dmg
# (create-dmg + a rendered background, same pattern as zStats).
# Run scripts/build-app.sh first.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="zWhisper"
APP_DIR="$ROOT/build/$APP_NAME.app"
VERSION="${1:-$(defaults read "$APP_DIR/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo 1.0.0)}"
DMG="$ROOT/build/$APP_NAME-$VERSION.dmg"

[ -d "$APP_DIR" ] || { echo "error: $APP_DIR not found, run scripts/build-app.sh first"; exit 1; }
command -v create-dmg >/dev/null || { echo "error: create-dmg not installed (brew install create-dmg)"; exit 1; }

STAGE="$(mktemp -d "$ROOT/build/dmg-stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP_DIR" "$STAGE/$APP_NAME.app"

ARTWORK="$ROOT/build/dmg-artwork"
mkdir -p "$ARTWORK"
swift "$ROOT/scripts/render-dmg-background.swift" "$ARTWORK/background.png"

echo "==> Creating $DMG"
rm -f "$DMG"
create-dmg \
    --volname "Install $APP_NAME" \
    --volicon "$APP_DIR/Contents/Resources/AppIcon.icns" \
    --background "$ARTWORK/background.png" \
    --window-pos 240 180 --window-size 720 468 \
    --icon-size 112 --text-size 14 \
    --icon "$APP_NAME.app" 200 218 --hide-extension "$APP_NAME.app" \
    --app-drop-link 520 218 \
    --format UDZO --filesystem HFS+ \
    "$DMG" "$STAGE" >/dev/null

echo "==> Done: $DMG"
