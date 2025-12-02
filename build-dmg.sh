#!/bin/bash
set -e

APP_NAME="ColimaBar"
DMG_NAME="$APP_NAME.dmg"
VOLUME_NAME="$APP_NAME"
APP_BUNDLE="$APP_NAME.app"

# Build the app first if needed
if [ ! -d "$APP_BUNDLE" ]; then
    echo "Building app first..."
    ./build-app.sh
fi

echo "Creating DMG..."

# Clean up any existing DMG
rm -f "$DMG_NAME"

# Create a temporary directory for DMG contents
DMG_TEMP="dmg_temp"
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"

# Copy the app bundle
cp -R "$APP_BUNDLE" "$DMG_TEMP/"

# Create a symbolic link to Applications
ln -s /Applications "$DMG_TEMP/Applications"

# Create the DMG
hdiutil create -volname "$VOLUME_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov -format UDZO \
    "$DMG_NAME"

# Clean up
rm -rf "$DMG_TEMP"

echo ""
echo "DMG created: $DMG_NAME"
echo "Size: $(du -h "$DMG_NAME" | cut -f1)"
