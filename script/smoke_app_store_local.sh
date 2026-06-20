#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-build}"
APP_NAME="AudioBar"
BUNDLE_ID="com.michaelvandijk.AudioBar"
MIN_SYSTEM_VERSION="14.2"
APP_VERSION="${APP_VERSION:-0.2.0}"
APP_BUILD="${APP_BUILD:-10}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist/app-store-smoke"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
APP_ICON="$APP_RESOURCES/$APP_NAME.icns"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ENTITLEMENTS_PLIST="$ROOT_DIR/Resources/AudioBar-AppStore.entitlements"
ICON_SOURCE="$ROOT_DIR/docs/assets/audiobar-app-icon.png"

cd "$ROOT_DIR"

rm -rf "$DIST_DIR"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"

swift build -c release --product "$APP_NAME" -Xswiftc -DAPP_STORE
BUILD_BINARY="$(swift build -c release --show-bin-path -Xswiftc -DAPP_STORE)/$APP_NAME"

cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

ICONSET="$DIST_DIR/$APP_NAME.iconset"
mkdir -p "$ICONSET"
sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP_ICON"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>AudioBar.icns</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>AudioBar controls supported media apps only when you use their playback or volume controls.</string>
  <key>NSAudioCaptureUsageDescription</key>
  <string>AudioBar captures system audio locally so the menu bar EQ can process it.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --sign - --entitlements "$ENTITLEMENTS_PLIST" "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

plutil -extract CFBundleIconFile raw "$INFO_PLIST" >/dev/null
plutil -extract NSAppleEventsUsageDescription raw "$INFO_PLIST" >/dev/null
plutil -extract NSAudioCaptureUsageDescription raw "$INFO_PLIST" >/dev/null

codesign -d --entitlements :- "$APP_BUNDLE" 2>/dev/null |
  grep -q "com.apple.security.app-sandbox"

if strings "$APP_BINARY" | rg 'System Events|MediaRemote|MRMediaRemote|key code 49|key code 125|key code 126'; then
  echo "Blocked automation string found in APP_STORE binary" >&2
  exit 1
fi

case "$MODE" in
  build|--build)
    echo "Local App Store smoke bundle staged at:"
    echo "$APP_BUNDLE"
    ;;
  launch|--launch)
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    /usr/bin/open -n "$APP_BUNDLE"
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    echo "Local App Store smoke launch verified."
    ;;
  *)
    echo "usage: $0 [build|launch]" >&2
    exit 2
    ;;
esac
