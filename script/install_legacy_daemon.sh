#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-install}"
APP_BUNDLE="${QUIETCOOLING_APP_BUNDLE:-/Applications/QuietCooling.app}"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/QuietCooling"
HELPER_BINARY="$APP_BUNDLE/Contents/MacOS/QuietCoolingHelper"
LABEL="com.mvandijk.QuietCooling.Helper"
APP_BUNDLE_ID="com.mvandijk.QuietCooling.MenuBar"
PLIST="/Library/LaunchDaemons/$LABEL.plist"

require_app() {
  if [[ ! -x "$APP_BINARY" ]]; then
    echo "Missing app executable: $APP_BINARY" >&2
    exit 1
  fi

  if [[ ! -x "$HELPER_BINARY" ]]; then
    echo "Missing helper executable: $HELPER_BINARY" >&2
    exit 1
  fi
}

write_plist() {
  local tmp
  tmp="$(mktemp)"
  cat >"$tmp" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$HELPER_BINARY</string>
  </array>
  <key>MachServices</key>
  <dict>
    <key>$LABEL</key>
    <true/>
  </dict>
  <key>AssociatedBundleIdentifiers</key>
  <array>
    <string>$APP_BUNDLE_ID</string>
  </array>
</dict>
</plist>
PLIST

  sudo install -m 644 -o root -g wheel "$tmp" "$PLIST"
  rm -f "$tmp"
}

install_daemon() {
  require_app
  sudo launchctl bootout system "$PLIST" >/dev/null 2>&1 || true
  write_plist
  sudo launchctl bootstrap system "$PLIST"
  sudo launchctl enable "system/$LABEL"
  sudo launchctl kickstart -k "system/$LABEL" >/dev/null 2>&1 || true
  "$APP_BINARY" --diagnose-helper
}

uninstall_daemon() {
  sudo launchctl bootout system "$PLIST" >/dev/null 2>&1 || true
  sudo rm -f "$PLIST"
}

status_daemon() {
  require_app
  launchctl print "system/$LABEL" 2>/dev/null || true
  "$APP_BINARY" --diagnose-helper
}

case "$ACTION" in
  install)
    install_daemon
    ;;
  uninstall)
    uninstall_daemon
    ;;
  status)
    status_daemon
    ;;
  *)
    echo "usage: $0 [install|uninstall|status]" >&2
    exit 2
    ;;
esac
