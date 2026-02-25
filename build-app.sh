#!/bin/bash
set -e

APP_NAME="Whisprr"
BUNDLE_ID="com.whisprr.app"
APP_DIR="$APP_NAME.app"

echo "Building release binary..."
swift build -c release

echo "Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp ".build/release/$APP_NAME" "$APP_DIR/Contents/MacOS/"

# Info.plist — LSUIElement=true hides the Dock icon (menu-bar-only app)
cat > "$APP_DIR/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Whisprr</string>
    <key>CFBundleDisplayName</key>
    <string>Whisprr</string>
    <key>CFBundleIdentifier</key>
    <string>com.whisprr.app</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
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

echo ""
echo "Done! $APP_DIR created."
echo ""
echo "To run:  open $APP_DIR"
echo "To install:  mv $APP_DIR /Applications/"
