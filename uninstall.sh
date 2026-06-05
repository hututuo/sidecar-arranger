#!/usr/bin/env bash
set -euo pipefail

LABEL="com.hyy.ipad-display-watcher"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
PURGE_CONFIG=0

if [[ "${1:-}" == "--purge-config" ]]; then
  PURGE_CONFIG=1
elif [[ $# -gt 0 ]]; then
  echo "Usage: ./uninstall.sh [--purge-config]" >&2
  exit 2
fi

launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
rm -f "$PLIST"
rm -f "$HOME/.local/bin/ipad-display-watcher" "$HOME/.local/bin/ipad-dialog"
rm -rf "$HOME/.local/ipad-display-watcher"

if [[ "$PURGE_CONFIG" -eq 1 ]]; then
  rm -rf "$HOME/.config/ipad-display-watcher"
fi

echo "Uninstalled ipad-display-watcher."
