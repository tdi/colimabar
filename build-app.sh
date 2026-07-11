#!/bin/bash
set -e

APP_NAME="ColimaBar"
BUILD_DIR=".build/apple/Products/Release"
APP_BUNDLE="$APP_NAME.app"

# Version: strip a leading "v" for Info.plist (v0.4 -> 0.4). Default dev value.
RAW_VERSION="${1:-0.0.0-dev}"
VERSION="${RAW_VERSION#v}"

echo "Building $APP_NAME $VERSION (universal)..."
swift build -c release --arch arm64 --arch x86_64

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"
cp "Sources/Info.plist" "$APP_BUNDLE/Contents/"

# Set version on the bundle's Info.plist copy. `Set` errors on a missing key,
# so a renamed/removed key fails the build instead of silently shipping wrong.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP_BUNDLE/Contents/Info.plist"

# Ad-hoc sign the assembled bundle. This generates _CodeSignature/CodeResources,
# which the linker's ad-hoc signature on the raw binary requires. Without it a
# downloaded (quarantined) app fails Gatekeeper as "damaged" (issue #4).
echo "Signing bundle (ad-hoc)..."
codesign --force --deep --sign - "$APP_BUNDLE"

# Hard gate: a bundle that does not validate must not reach a DMG.
echo "Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "App bundle created and signed at $APP_BUNDLE"
