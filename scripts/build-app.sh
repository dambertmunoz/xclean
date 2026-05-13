#!/usr/bin/env bash
#
# build-app.sh — packages the xclean SPM binary into a proper macOS .app
# bundle. The bundle's Info.plist supplies the missing CFBundleIdentifier
# that UNUserNotificationCenter and other macOS APIs require, and sets
# LSUIElement=YES so the app stays out of the Dock / Cmd-Tab.
#
# Usage:
#   ./scripts/build-app.sh                # build, install to /Applications
#   ./scripts/build-app.sh skip           # build only (no install)
#   ./scripts/build-app.sh /tmp           # install to /tmp/xclean.app
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BINARY="$ROOT/.build/release/xclean"
BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/xclean.app"
DEST="${1:-/Applications}"

VERSION="0.2.0"
BUNDLE_ID="com.dambert.xclean"

echo "→ building release binary"
cd "$ROOT"
swift build -c release >/dev/null

if [[ ! -x "$BINARY" ]]; then
    echo "error: missing $BINARY after swift build" >&2
    exit 1
fi

echo "→ assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BINARY" "$APP_DIR/Contents/MacOS/xclean"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>xclean</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>xclean</string>
    <key>CFBundleDisplayName</key>
    <string>xclean</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 Dambert Munoz</string>
</dict>
</plist>
PLIST

echo "✓ built $APP_DIR"

if [[ "$DEST" == "skip" ]]; then
    echo "  (skip install)"
    exit 0
fi

if [[ -d "$DEST/xclean.app" ]]; then
    echo "→ removing previous $DEST/xclean.app"
    rm -rf "$DEST/xclean.app"
fi
echo "→ installing to $DEST/xclean.app"
mkdir -p "$DEST"
cp -R "$APP_DIR" "$DEST/xclean.app"

# Optional: ad-hoc codesign so Gatekeeper is calmer. Real signing requires
# a Developer ID — left to the user.
if command -v codesign >/dev/null 2>&1; then
    echo "→ ad-hoc codesigning"
    codesign --force --deep --sign - "$DEST/xclean.app" >/dev/null 2>&1 || true
fi

echo "✓ installed $DEST/xclean.app"
echo ""
echo "Next steps:"
echo "  - Quit any running 'xclean menu' (Quit from the menu bar item)."
echo "  - Open the new app:        open $DEST/xclean.app"
echo "  - Re-run the LaunchAgent:  ./scripts/install-launch-agent.sh"
echo ""
echo "The LaunchAgent will now prefer $DEST/xclean.app/Contents/MacOS/xclean."
