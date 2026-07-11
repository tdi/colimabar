#!/bin/bash
set -e

APP_NAME="ColimaBar"
VOLUME_NAME="$APP_NAME"
APP_BUNDLE="$APP_NAME.app"

RAW_VERSION="${1:-0.0.0-dev}"
DMG_NAME="$APP_NAME-$RAW_VERSION.dmg"

# Always rebuild the bundle so the DMG can never contain a stale app.
echo "Building app bundle..."
./build-app.sh "$RAW_VERSION"

echo "Creating DMG $DMG_NAME..."
rm -f "$DMG_NAME"

DMG_TEMP="dmg_temp"
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"

cp -R "$APP_BUNDLE" "$DMG_TEMP/"
ln -s /Applications "$DMG_TEMP/Applications"

hdiutil create -volname "$VOLUME_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov -format UDZO \
    "$DMG_NAME"

rm -rf "$DMG_TEMP"

echo ""
echo "DMG created: $DMG_NAME"
echo "Size: $(du -h "$DMG_NAME" | cut -f1)"
