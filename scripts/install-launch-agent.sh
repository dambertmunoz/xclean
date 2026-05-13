#!/usr/bin/env bash
#
# install-launch-agent.sh — register xclean menu as a LaunchAgent so it
# starts automatically at login and is relaunched if it crashes.
#
# Usage:
#   ./scripts/install-launch-agent.sh         install + load
#   ./scripts/install-launch-agent.sh --uninstall   stop + remove
#
set -euo pipefail

LABEL="com.dambert.xclean"
AGENT_PATH="$HOME/Library/LaunchAgents/${LABEL}.plist"
LOG_DIR="$HOME/Library/Logs/xclean"
BIN_PATH="$(command -v xclean || true)"

if [[ "${1:-}" == "--uninstall" ]]; then
  echo "→ unloading $LABEL"
  launchctl bootout "gui/$(id -u)" "$AGENT_PATH" 2>/dev/null || true
  rm -f "$AGENT_PATH"
  echo "removed $AGENT_PATH"
  exit 0
fi

APP_BINARY="/Applications/xclean.app/Contents/MacOS/xclean"
if [[ -x "$APP_BINARY" ]]; then
  BIN_PATH="$APP_BINARY"
  echo "  using app bundle at $BIN_PATH"
fi

if [[ -z "$BIN_PATH" ]]; then
  echo "error: xclean not found in PATH. Install it first:" >&2
  echo "  swift build -c release && cp .build/release/xclean /opt/homebrew/bin/" >&2
  echo "  (or: ./scripts/build-app.sh)" >&2
  exit 1
fi

mkdir -p "$LOG_DIR"

cat > "$AGENT_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>

    <key>ProgramArguments</key>
    <array>
        <string>${BIN_PATH}</string>
        <string>menu</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>

    <key>ProcessType</key>
    <string>Interactive</string>

    <key>StandardOutPath</key>
    <string>${LOG_DIR}/xclean.out.log</string>

    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/xclean.err.log</string>
</dict>
</plist>
PLIST

echo "→ wrote $AGENT_PATH"

# Reload (bootout + bootstrap so the new plist is picked up).
launchctl bootout "gui/$(id -u)" "$AGENT_PATH" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$AGENT_PATH"
launchctl kickstart -k "gui/$(id -u)/${LABEL}"

echo "✓ xclean menu loaded. Logs: $LOG_DIR/xclean.*.log"
echo "  Uninstall with: $0 --uninstall"
