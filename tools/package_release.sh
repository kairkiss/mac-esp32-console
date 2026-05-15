#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/macos/MacESP32Console"
VERSION="${1:-7.0.0-alpha1}"
FORCE="${2:-}"

APP_NAME="Mac-esp32控制台"
PRODUCT_NAME="MacESP32Console"
BUNDLE_ID="com.biankai.macesp32console"
SCRATCH="${TMPDIR:-/tmp}/MacESP32Console.release.${VERSION}"
BUILD_ROOT="${TMPDIR:-/tmp}/mac-esp32-console-${VERSION}"
APP="$BUILD_ROOT/$APP_NAME.app"
DIST="$ROOT/dist"
ZIP="$DIST/Mac-esp32-console-v${VERSION}-macOS.zip"
NOTES="$DIST/RELEASE_NOTES_v${VERSION}.md"

if [[ -e "$ZIP" || -e "$NOTES" ]]; then
  if [[ "$FORCE" != "--force" ]]; then
    echo "release artifacts already exist. Re-run with --force to overwrite:" >&2
    echo "  $ZIP" >&2
    echo "  $NOTES" >&2
    exit 2
  fi
fi

rm -rf "$SCRATCH" "$BUILD_ROOT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$DIST"

swift build --package-path "$PROJECT" --configuration release --scratch-path "$SCRATCH"
BIN_PATH="$(swift build --package-path "$PROJECT" --configuration release --scratch-path "$SCRATCH" --show-bin-path)"

cp "$BIN_PATH/$PRODUCT_NAME" "$APP/Contents/MacOS/$PRODUCT_NAME"
if [[ -f "$PROJECT/Resources/MacESP32Console.icns" ]]; then
  cp "$PROJECT/Resources/MacESP32Console.icns" "$APP/Contents/Resources/MacESP32Console.icns"
fi
chmod +x "$APP/Contents/MacOS/$PRODUCT_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleExecutable</key>
  <string>$PRODUCT_NAME</string>
  <key>CFBundleIconFile</key>
  <string>MacESP32Console</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>7001</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

rm -f "$ZIP" "$NOTES"
(cd "$BUILD_ROOT" && ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$ZIP")

SHA="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
DATE="$(date +%Y-%m-%d)"

cat > "$NOTES" <<NOTES
# Mac-ESP32 Console v${VERSION}

Date: ${DATE}
Git commit: ${SHA}

## Highlights

- ESP32 OTA status and LAN firmware upload first stage.
- Device page: richer status fields, status copy, diagnostic export, test expression and widget buttons.
- Network recovery: Mac IP drift detection and \`network_reason\` reporting.
- DisplayKit: coding, music, calendar, night, dreamcore, diagnostics, OTA, network error, and dashboard scene presets.
- Mac ecosystem providers: foreground window context and best-effort now-playing metadata.
- Telegram \`/wake\` now wakes the OLED instead of implying Mac wake.
- Menu bar icon is now a robot SF Symbol with fallback.

## Known Limits

- OTA requires an OTA-capable ESP32 partition layout and enough free sketch space.
- OTA alpha1 is intended for trusted LAN use.
- Calendar provider is a placeholder.
- Now Playing is best effort and depends on local app permissions/state.

## OTA Notes

Read \`docs/OTA_UPDATE.md\` before uploading firmware. If \`/ota/status\` reports unsupported, use USB flashing with an OTA-capable partition scheme first.
NOTES

echo "$ZIP"
echo "$NOTES"
