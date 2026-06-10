#!/usr/bin/env bash
set -euo pipefail

APP_NAME="AudioBar"
BUNDLE_ID="com.michaelvandijk.AudioBar"
MIN_SYSTEM_VERSION="14.2"
APP_VERSION="${APP_VERSION:-0.1.4}"
APP_BUILD="${APP_BUILD:-5}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_STORE_DIR="$DIST_DIR/app-store"
APP_BUNDLE="$APP_STORE_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
APP_ICON="$APP_RESOURCES/$APP_NAME.icns"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ENTITLEMENTS_PLIST="$ROOT_DIR/Resources/AudioBar-AppStore.entitlements"
ICON_SOURCE="$ROOT_DIR/docs/assets/audiobar-popover-eq-expanded.png"
PKG_PATH="$APP_STORE_DIR/$APP_NAME-AppStore.pkg"
APP_STORE_PROVISIONING_PROFILE="${APP_STORE_PROVISIONING_PROFILE:-}"
APP_STORE_APP_SIGN_IDENTITY="${APP_STORE_APP_SIGN_IDENTITY:-}"
APP_STORE_INSTALLER_SIGN_IDENTITY="${APP_STORE_INSTALLER_SIGN_IDENTITY:-}"
APP_STORE_CONNECT_USERNAME="${APP_STORE_CONNECT_USERNAME:-}"
APP_STORE_CONNECT_PASSWORD="${APP_STORE_CONNECT_PASSWORD:-}"

cd "$ROOT_DIR"

if [[ -z "$APP_STORE_APP_SIGN_IDENTITY" ]]; then
  APP_STORE_APP_SIGN_IDENTITY="$(
    security find-identity -v -p codesigning |
      sed -n 's/.*"\(3rd Party Mac Developer Application: [^"]*\)".*/\1/p; s/.*"\(Apple Distribution: [^"]*\)".*/\1/p' |
      head -n 1
  )"
fi

if [[ -z "$APP_STORE_INSTALLER_SIGN_IDENTITY" ]]; then
  APP_STORE_INSTALLER_SIGN_IDENTITY="$(
    security find-identity -v -p basic |
      sed -n 's/.*"\(3rd Party Mac Developer Installer: [^"]*\)".*/\1/p; s/.*"\(Mac Installer Distribution: [^"]*\)".*/\1/p' |
      head -n 1
  )"
fi

if [[ -z "$APP_STORE_APP_SIGN_IDENTITY" ]]; then
  cat >&2 <<ERROR
Missing App Store application signing identity.

Install a Mac App Store application distribution certificate, or pass:
  APP_STORE_APP_SIGN_IDENTITY="3rd Party Mac Developer Application: Your Name (TEAMID)" $0
ERROR
  exit 2
fi

if [[ -z "$APP_STORE_INSTALLER_SIGN_IDENTITY" ]]; then
  cat >&2 <<ERROR
Missing App Store installer signing identity.

Install a Mac App Store installer distribution certificate, or pass:
  APP_STORE_INSTALLER_SIGN_IDENTITY="3rd Party Mac Developer Installer: Your Name (TEAMID)" $0
ERROR
  exit 2
fi

if [[ -z "$APP_STORE_PROVISIONING_PROFILE" || ! -f "$APP_STORE_PROVISIONING_PROFILE" ]]; then
  cat >&2 <<ERROR
Missing App Store provisioning profile.

Pass a downloaded Mac App Store provisioning profile:
  APP_STORE_PROVISIONING_PROFILE="/path/to/profile.provisionprofile" $0
ERROR
  exit 2
fi

rm -rf "$APP_STORE_DIR"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"

swift build -c release --product "$APP_NAME" -Xswiftc -DAPP_STORE
BUILD_BINARY="$(swift build -c release --show-bin-path -Xswiftc -DAPP_STORE)/$APP_NAME"

cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$APP_STORE_PROVISIONING_PROFILE" "$APP_CONTENTS/embedded.provisionprofile"

if [[ -f "$ICON_SOURCE" ]]; then
  ICONSET="$APP_STORE_DIR/$APP_NAME.iconset"
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
else
  echo "Missing icon source: $ICON_SOURCE" >&2
  exit 2
fi

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

codesign \
  --force \
  --entitlements "$ENTITLEMENTS_PLIST" \
  --timestamp \
  --sign "$APP_STORE_APP_SIGN_IDENTITY" \
  "$APP_BUNDLE"

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
productbuild \
  --component "$APP_BUNDLE" /Applications \
  --sign "$APP_STORE_INSTALLER_SIGN_IDENTITY" \
  "$PKG_PATH"

if [[ -n "$APP_STORE_CONNECT_USERNAME" && -n "$APP_STORE_CONNECT_PASSWORD" ]]; then
  xcrun altool --validate-app "$PKG_PATH" \
    --username "$APP_STORE_CONNECT_USERNAME" \
    --password "$APP_STORE_CONNECT_PASSWORD"
else
  echo "Skipping App Store validation because App Store Connect credentials were not provided."
  echo "Run validation with:"
  echo "  APP_STORE_CONNECT_USERNAME=<apple-id> APP_STORE_CONNECT_PASSWORD=<app-specific-password-or-keychain-ref> $0"
fi

echo "Created App Store candidate package:"
echo "$PKG_PATH"
