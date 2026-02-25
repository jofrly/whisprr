#!/bin/bash
set -e

APP_NAME="Whisprr"
BUNDLE_ID="com.whisprr.app"
APP_DIR="$APP_NAME.app"
DMG_NAME="$APP_NAME.dmg"
VOLUME_NAME="$APP_NAME"

# Current version (update this each release)
CURRENT_VERSION="1.0.1"

echo "Current version: $CURRENT_VERSION"
printf "New version number: "
read -r NEW_VERSION

if [ -z "$NEW_VERSION" ]; then
    echo "No version entered, aborting."
    exit 1
fi

echo ""
echo "Building release binary..."
swift build -c release

echo "Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp ".build/release/$APP_NAME" "$APP_DIR/Contents/MacOS/"

# Info.plist — LSUIElement=true hides the Dock icon (menu-bar-only app)
cat > "$APP_DIR/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Whisprr</string>
    <key>CFBundleDisplayName</key>
    <string>Whisprr</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>${NEW_VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${NEW_VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>Whisprr</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Whisprr needs microphone access to record audio for transcription.</string>
</dict>
</plist>
PLIST

echo "Creating DMG..."
STAGING_DIR=$(mktemp -d)

cp -R "$APP_DIR" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_NAME"

hdiutil create "$DMG_NAME" \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO

rm -rf "$STAGING_DIR"

# Update this script's CURRENT_VERSION for next time
sed -i '' "s/^CURRENT_VERSION=\".*\"/CURRENT_VERSION=\"$NEW_VERSION\"/" "$0"

echo ""
echo "Done! $APP_DIR and $DMG_NAME created (version $NEW_VERSION)."
echo ""
echo "To run:     open $APP_DIR"
echo "To install: open $DMG_NAME"
