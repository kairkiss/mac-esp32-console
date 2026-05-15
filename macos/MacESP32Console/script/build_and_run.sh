#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Mac-esp32控制台"
PRODUCT_NAME="MacESP32Console"
BUNDLE_ID="com.biankai.macesp32console"
DIST_DIR="$PWD/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DESKTOP_APP="$HOME/Desktop/$APP_NAME.app"

swift build -c debug

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp ".build/debug/$PRODUCT_NAME" "$APP_BUNDLE/Contents/MacOS/$PRODUCT_NAME"
if [[ -f "Resources/MacESP32Console.icns" ]]; then
  cp "Resources/MacESP32Console.icns" "$APP_BUNDLE/Contents/Resources/MacESP32Console.icns"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleExecutable</key>
  <string>$PRODUCT_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>MacESP32Console</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>6.6.0</string>
  <key>CFBundleVersion</key>
  <string>6.6.0</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

if [[ "${1:-}" == "--install-desktop" ]]; then
  rm -rf "$DESKTOP_APP"
  cp -R "$APP_BUNDLE" "$DESKTOP_APP"
  APP_BUNDLE="$DESKTOP_APP"
fi

pkill -x "$PRODUCT_NAME" 2>/dev/null || true
/usr/bin/open "$APP_BUNDLE"

if [[ "${1:-}" == "--verify" || "${2:-}" == "--verify" ]]; then
  sleep 4
  pgrep -x "$PRODUCT_NAME" >/dev/null
fi
