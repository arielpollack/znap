#!/bin/bash
set -euo pipefail

APP_NAME="Znap"
APP_PATH="build/Build/Products/Release/${APP_NAME}.app"
DMG_NAME="${APP_NAME}.dmg"
DMG_TEMP="${APP_NAME}-temp.dmg"
VOLUME_NAME="${APP_NAME}"
DMG_DIR="dmg_staging"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: ${APP_PATH} not found. Run 'make build' first."
    exit 1
fi

echo "Creating DMG for ${APP_NAME}..."

# Clean up any previous staging
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"

# Copy app to staging
cp -R "$APP_PATH" "$DMG_DIR/"

# Create symlink to /Applications
ln -s /Applications "$DMG_DIR/Applications"

# Create temporary DMG
hdiutil create -volname "$VOLUME_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov -format UDRW \
    "$DMG_TEMP"

# Convert to compressed DMG
hdiutil convert "$DMG_TEMP" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_NAME"

# Clean up
rm -rf "$DMG_DIR"
rm -f "$DMG_TEMP"

echo "DMG created: ${DMG_NAME}"
