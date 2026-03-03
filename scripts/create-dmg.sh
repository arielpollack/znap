#!/bin/bash
set -euo pipefail

APP_NAME="Znap"
APP_PATH="build/Build/Products/Release/${APP_NAME}.app"

# Get version from Info.plist inside the built app
VERSION=$(defaults read "$(pwd)/${APP_PATH}/Contents/Info" CFBundleShortVersionString)
DMG_NAME="${APP_NAME}-${VERSION}.dmg"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: ${APP_PATH} not found. Run 'make build' first."
    exit 1
fi

# Remove previous DMG if exists
rm -f "$DMG_NAME"

echo "Creating DMG for ${APP_NAME} v${VERSION}..."

create-dmg \
    --volname "${APP_NAME}" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "${APP_NAME}.app" 150 185 \
    --app-drop-link 450 185 \
    --no-internet-enable \
    "$DMG_NAME" \
    "$APP_PATH"

echo "DMG created: ${DMG_NAME}"
