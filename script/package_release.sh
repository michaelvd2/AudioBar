#!/usr/bin/env bash
set -euo pipefail

APP_NAME="AudioBar"
BUNDLE_ID="com.michaelvandijk.AudioBar"
MIN_SYSTEM_VERSION="14.0"
APP_VERSION="0.1.3"
BUILD_NUMBER="4"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
RELEASE_DIR="$DIST_DIR/release"
APP_BUNDLE="$RELEASE_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ENTITLEMENTS_PLIST="$ROOT_DIR/Resources/AudioBar.entitlements"
SIGNED_ZIP="$RELEASE_DIR/AudioBar-signed.zip"
NOTARIZED_ZIP="$RELEASE_DIR/AudioBar-notarized.zip"

DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION:-}"
NOTARYTOOL_PROFILE="${NOTARYTOOL_PROFILE:-}"

cd "$ROOT_DIR"

if [[ -z "$DEVELOPER_ID_APPLICATION" ]]; then
  detected_identity="$(
    security find-identity -v -p codesigning |
      sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' |
      head -n 1
  )"
  DEVELOPER_ID_APPLICATION="$detected_identity"
fi

if [[ -z "$DEVELOPER_ID_APPLICATION" ]]; then
  cat >&2 <<ERROR
Missing Developer ID Application signing identity.

This Mac currently cannot create a zip that opens cleanly on other Macs.
Install a Developer ID Application certificate, or pass:
  DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)" $0
ERROR
  exit 2
fi

if [[ -z "$NOTARYTOOL_PROFILE" ]]; then
  cat >&2 <<ERROR
Missing notarytool credentials profile.

Create one first, for example:
  xcrun notarytool store-credentials "AudioBar Notary" --apple-id <apple-id> --team-id <team-id> --password <app-specific-password>

Then run:
  NOTARYTOOL_PROFILE="AudioBar Notary" $0
ERROR
  exit 2
fi

rm -rf "$RELEASE_DIR"
mkdir -p "$APP_MACOS"

swift build -c release --product "$APP_NAME"
BUILD_BINARY="$(swift build -c release --show-bin-path)/$APP_NAME"

cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSAudioCaptureUsageDescription</key>
  <string>AudioBar captures system audio so the menu bar EQ can process it.</string>
  <key>NSInputMonitoringUsageDescription</key>
  <string>AudioBar sends the system play/pause media key so web audio can be paused without switching apps.</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>AudioBar controls Music, Spotify, Safari, and System Events only when you use source volume or playback controls.</string>
</dict>
</plist>
PLIST

codesign \
  --force \
  --deep \
  --entitlements "$ENTITLEMENTS_PLIST" \
  --options runtime \
  --timestamp \
  --sign "$DEVELOPER_ID_APPLICATION" \
  "$APP_BUNDLE"

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
ditto -c -k --keepParent "$APP_BUNDLE" "$SIGNED_ZIP"

xcrun notarytool submit "$SIGNED_ZIP" \
  --keychain-profile "$NOTARYTOOL_PROFILE" \
  --wait

xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"
spctl -a -vv "$APP_BUNDLE"

rm -f "$NOTARIZED_ZIP"
ditto -c -k --keepParent "$APP_BUNDLE" "$NOTARIZED_ZIP"

echo "Created notarized release zip:"
echo "$NOTARIZED_ZIP"
