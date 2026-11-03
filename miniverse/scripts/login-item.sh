#!/usr/bin/env bash
# Keeps the Miniverse server running from login, as a macOS LaunchAgent.
#
#   scripts/login-item.sh install     write the LaunchAgent and start it now
#   scripts/login-item.sh uninstall   stop it and remove the LaunchAgent
#   scripts/login-item.sh status      show whether it is loaded and serving
#
# It runs `npm run dev` (Miniverse server on 4321 and the world on 5180) and restarts it if it
# dies. It doesn't open any window: the team plugin's team-miniverse does that when a team
# session starts, and builds the office for that project.
#
# Before each start it forgets which project's office is shown (~/.claude/team-miniverse/project).
# team-miniverse only opens the window when the server is new or the project changed; without
# this, the first team session after a reboot would find the same project and open nothing.

set -euo pipefail

LABEL="com.marcperez.miniverse"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="$HOME/.claude/team-miniverse"
DOMAIN="gui/$(id -u)"

# launchd starts with a bare PATH: use the npm that's on the PATH now (nvm included).
NPM="$(command -v npm || true)"

case "${1:-}" in
  install)
    [[ -n "$NPM" ]] || { echo "login-item: npm not found on the PATH" >&2; exit 1; }
    [[ -d "$APP_DIR/node_modules" ]] || (cd "$APP_DIR" && npm install --no-fund --no-audit)
    mkdir -p "$LOG_DIR" "$(dirname "$PLIST")"
    cat >"$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/sh</string>
    <string>-c</string>
    <string>rm -f '$LOG_DIR/project'; exec '$NPM' run dev</string>
  </array>
  <key>WorkingDirectory</key>
  <string>$APP_DIR</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>$(dirname "$NPM"):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$LOG_DIR/server.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/server.log</string>
</dict>
</plist>
PLIST
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    launchctl bootstrap "$DOMAIN" "$PLIST"
    echo "login-item: installed ($PLIST), Miniverse starts at login"
    ;;
  uninstall)
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"
    echo "login-item: removed"
    ;;
  status)
    if launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then echo "loaded: yes"; else echo "loaded: no"; fi
    curl -s -m 2 -o /dev/null -w "server 4321: %{http_code}\n" http://127.0.0.1:4321/api/agents || echo "server 4321: down"
    curl -s -m 2 -o /dev/null -w "world  5180: %{http_code}\n" http://127.0.0.1:5180/ || echo "world  5180: down"
    ;;
  *)
    echo "Usage: scripts/login-item.sh install|uninstall|status" >&2
    exit 1
    ;;
esac
