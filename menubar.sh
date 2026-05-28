#!/usr/bin/env bash
# menubar.sh — build, launch, and manage the claude-geiger macOS menu bar toggle.
#
# Usage:
#   ./menubar.sh            build (if needed) and (re)launch the menu bar app
#   ./menubar.sh --stop     quit the running menu bar app
#   ./menubar.sh --login    also install a LaunchAgent so it starts at login
#   ./menubar.sh --logout   remove that LaunchAgent (does not stop the app)
#
# macOS only — uses swiftc to build a SwiftUI MenuBarExtra app. It puts a ☢
# in your menu bar; click it to mute/unmute geiger clicks live (no Claude Code
# restart needed).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/geigerbar.swift"
APP="$SCRIPT_DIR/GeigerBar.app"
BIN="$APP/Contents/MacOS/geigerbar"
BUNDLE_ID="com.claude-geiger.menubar"
PLIST="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"

if [ "$(uname)" != "Darwin" ]; then
  echo "The menu bar toggle is macOS only (this is $(uname))."
  echo "On other platforms, mute by writing 0 to ~/.config/claude-geiger/enabled."
  exit 1
fi
command -v swiftc >/dev/null 2>&1 || {
  echo "swiftc not found. Install Xcode command line tools: xcode-select --install"
  exit 1
}

build() {
  # Package as a proper .app bundle so the Info.plist (LSUIElement: menu-bar-only
  # agent, no Dock icon) and code signature apply — a bare executable has neither.
  if [ -x "$BIN" ] && [ "$BIN" -nt "$SRC" ]; then return; fi
  echo "Building GeigerBar.app..."
  mkdir -p "$APP/Contents/MacOS"
  # -parse-as-library so the SwiftUI @main App entry point works.
  swiftc -O -parse-as-library "$SRC" -o "$BIN"
  cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>GeigerBar</string>
  <key>CFBundleDisplayName</key><string>Geiger</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>geigerbar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict>
</plist>
EOF
  # Ad-hoc sign so macOS registers the app's UI cleanly.
  codesign --force --sign - "$APP" >/dev/null 2>&1 || true
}

stop() {
  pkill -f "$BIN" 2>/dev/null && echo "Stopped menu bar app." || echo "Not running."
}

start() {
  build
  stop >/dev/null 2>&1 || true
  sleep 0.3
  open "$APP"
  echo "Menu bar app running — look for the ☢/atom icon at the top-right."
  echo "Click it to mute/unmute. Quit it from its own menu or: ./menubar.sh --stop"
}

install_login() {
  build
  stop >/dev/null 2>&1 || true   # avoid a duplicate alongside the launchd one
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$BUNDLE_ID</string>
  <key>ProgramArguments</key><array><string>$BIN</string></array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
EOF
  launchctl unload "$PLIST" 2>/dev/null || true
  launchctl load "$PLIST"   # RunAtLoad starts it now and at every login
  echo "Installed login item -> $PLIST (starts at login)."
}

remove_login() {
  if [ -f "$PLIST" ]; then
    launchctl unload "$PLIST" 2>/dev/null || true
    rm -f "$PLIST"
    echo "Removed login item."
  else
    echo "No login item installed."
  fi
}

case "${1:-}" in
  --stop)   stop ;;
  --login)  install_login ;;
  --logout) remove_login ;;
  "")       start ;;
  *)        echo "Unknown option: $1"; echo "Use: --stop | --login | --logout (or no arg to launch)"; exit 1 ;;
esac
