#!/bin/bash
set -e

VERSION=${1:-"1.0.0"}
APP_NAME="cc-menu"
APP_BUNDLE="${APP_NAME}.app"

echo "Building universal binary..."
swift build -c release --arch arm64 --arch x86_64

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"

cp .build/apple/Products/Release/"$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.mastericez.cc-menu</string>
    <key>CFBundleName</key>
    <string>cc-menu</string>
    <key>CFBundleDisplayName</key>
    <string>CC Menu</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "Zipping..."
zip -r "${APP_NAME}.zip" "$APP_BUNDLE"
shasum -a 256 "${APP_NAME}.zip"

echo "Done: ${APP_NAME}.zip"
