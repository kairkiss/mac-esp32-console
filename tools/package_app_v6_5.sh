#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/macos/MacESP32Console"
SCRATCH="${TMPDIR:-/tmp}/MacESP32Console.v65-release-build"
DIST="${TMPDIR:-/tmp}/mac-esp32-console-v6.5"
APP="$DIST/Mac-esp32控制台.app"
ZIP="$ROOT/dist/Mac-esp32-console-v6.5.0-macOS.zip"

rm -rf "$SCRATCH" "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/dist"

swift build --package-path "$PROJECT" --configuration release --scratch-path "$SCRATCH"

cp "$SCRATCH/x86_64-apple-macosx/release/MacESP32Console" "$APP/Contents/MacOS/MacESP32Console"
cp "$PROJECT/Resources/MacESP32Console.icns" "$APP/Contents/Resources/MacESP32Console.icns"
chmod +x "$APP/Contents/MacOS/MacESP32Console"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>MacESP32Console</string>
    <key>CFBundleIconFile</key>
    <string>MacESP32Console</string>
    <key>CFBundleIdentifier</key>
    <string>com.biankai.macesp32console</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Mac-esp32控制台</string>
    <key>CFBundleDisplayName</key>
    <string>Mac-esp32控制台</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.6.5</string>
    <key>CFBundleVersion</key>
    <string>65</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

rm -f "$ZIP"
(cd "$DIST" && ditto -c -k --sequesterRsrc --keepParent "Mac-esp32控制台.app" "$ZIP")

echo "$ZIP"
