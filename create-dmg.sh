#!/bin/bash
set -e

APP_NAME="Whisprr"
DMG_NAME="$APP_NAME.dmg"
VOLUME_NAME="$APP_NAME"
APP_DIR="$APP_NAME.app"
STAGING_DIR=$(mktemp -d)

# Build the app if it doesn't exist
if [ ! -d "$APP_DIR" ]; then
    echo "Building $APP_DIR..."
    ./build-app.sh
fi

echo "Creating DMG..."

# Set up staging directory with app and Applications symlink
cp -R "$APP_DIR" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

# Remove any existing DMG
rm -f "$DMG_NAME"

# Create the DMG
hdiutil create "$DMG_NAME" \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO

# Clean up
rm -rf "$STAGING_DIR"

echo ""
echo "Done! $DMG_NAME created."
echo ""
echo "To install:  open $DMG_NAME"
