#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="QuietCooling"
BUNDLE_ID="com.mvandijk.QuietCooling.MenuBar"
HELPER_NAME="QuietCoolingHelper"
HELPER_LABEL="com.mvandijk.QuietCooling.Helper"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
INSTALLED_APP_BUNDLE="/Applications/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
HELPER_BINARY="$APP_MACOS/$HELPER_NAME"
APP_LIBRARY="$APP_CONTENTS/Library"
LAUNCH_DAEMONS="$APP_LIBRARY/LaunchDaemons"
HELPER_PLIST="$LAUNCH_DAEMONS/$HELPER_LABEL.plist"
INFO_PLIST="$APP_CONTENTS/Info.plist"

cd "$ROOT_DIR"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
pkill -f "macmon serve --port 19191 --interval 1000" >/dev/null 2>&1 || true

swift build --product "$APP_NAME"
swift build --product "$HELPER_NAME"
BUILD_DIR="$(swift build --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"
BUILD_HELPER_BINARY="$BUILD_DIR/$HELPER_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
mkdir -p "$LAUNCH_DAEMONS"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$BUILD_HELPER_BINARY" "$HELPER_BINARY"
chmod +x "$APP_BINARY"
chmod +x "$HELPER_BINARY"

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
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

printf "APPL????" >"$APP_CONTENTS/PkgInfo"

cat >"$HELPER_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$HELPER_LABEL</string>
  <key>BundleProgram</key>
  <string>Contents/MacOS/$HELPER_NAME</string>
  <key>MachServices</key>
  <dict>
    <key>$HELPER_LABEL</key>
    <true/>
  </dict>
  <key>AssociatedBundleIdentifiers</key>
  <array>
    <string>$BUNDLE_ID</string>
  </array>
</dict>
</plist>
PLIST

choose_signing_identity() {
  if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    echo "$CODESIGN_IDENTITY"
    return
  fi

  local developer_id="Developer ID Application: Michael van Dijk (483T33H348)"
  local apple_development="Apple Development: michaelvd3@gmail.com (6Z6SJT3969)"

  if security find-identity -p codesigning -v 2>/dev/null | grep -Fq "$developer_id"; then
    echo "$developer_id"
  elif security find-identity -p codesigning -v 2>/dev/null | grep -Fq "$apple_development"; then
    echo "$apple_development"
  else
    echo "-"
  fi
}

SIGNING_IDENTITY="$(choose_signing_identity)"
codesign --force --options runtime --timestamp=none --sign "$SIGNING_IDENTITY" "$HELPER_BINARY"
codesign --force --options runtime --timestamp=none --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"

open_app() {
  rm -rf "$INSTALLED_APP_BUNDLE"
  ditto "$APP_BUNDLE" "$INSTALLED_APP_BUNDLE"
  /usr/bin/open "$INSTALLED_APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
