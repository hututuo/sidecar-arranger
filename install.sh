#!/usr/bin/env bash
set -euo pipefail

LABEL="com.hyy.ipad-display-watcher"
SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
ROOT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" 2>/dev/null && pwd || pwd)"
RAW_BASE="${IPAD_DISPLAY_WATCHER_RAW_BASE:-https://raw.githubusercontent.com/hututuo/ipad-display-watcher/main}"
SRC_DIR="$HOME/.local/ipad-display-watcher"
BIN_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config/ipad-display-watcher"
CONFIG_FILE="$CONFIG_DIR/known-monitors.txt"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs"
START_SERVICE=1
KNOWN_MONITORS=()
TMP_DIR=""

cleanup() {
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

One-line remote install:
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/hututuo/ipad-display-watcher/main/install.sh)"

Options:
  --known-monitor VENDOR:MODEL  Add an external monitor that should not prompt
  --no-start                    Build and install, but do not start LaunchAgent
  -h, --help                    Show this help

Examples:
  ./install.sh
  ./install.sh --known-monitor 19491:9571
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/hututuo/ipad-display-watcher/main/install.sh)"
EOF
}

source_file() {
  local name="$1"
  local local_path="$ROOT_DIR/$name"

  if [[ -f "$local_path" ]]; then
    printf '%s\n' "$local_path"
    return 0
  fi

  command -v curl >/dev/null || {
    echo "curl is required for remote install mode." >&2
    exit 1
  }

  if [[ -z "$TMP_DIR" ]]; then
    TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ipad-display-watcher.XXXXXX")"
  fi

  local remote_path="$TMP_DIR/$name"
  echo "Downloading $name from $RAW_BASE/$name" >&2
  curl -fsSL "$RAW_BASE/$name" -o "$remote_path"
  printf '%s\n' "$remote_path"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --known-monitor)
      [[ $# -ge 2 ]] || { echo "missing value for --known-monitor" >&2; exit 2; }
      KNOWN_MONITORS+=("$2")
      shift 2
      ;;
    --no-start)
      START_SERVICE=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This installer is for macOS." >&2
  exit 1
fi

command -v clang >/dev/null || {
  echo "clang is required. Install Xcode Command Line Tools first: xcode-select --install" >&2
  exit 1
}

WATCHER_SOURCE="$(source_file ipad-display-watcher.c)"
DIALOG_SOURCE="$(source_file ipad-dialog.m)"

mkdir -p "$SRC_DIR" "$BIN_DIR" "$CONFIG_DIR" "$LOG_DIR" "$(dirname "$PLIST")"
install -m 0644 "$WATCHER_SOURCE" "$SRC_DIR/ipad-display-watcher.c"
install -m 0644 "$DIALOG_SOURCE" "$SRC_DIR/ipad-dialog.m"

clang "$SRC_DIR/ipad-dialog.m" \
  -o "$BIN_DIR/ipad-dialog" \
  -framework Cocoa \
  -O2

clang "$SRC_DIR/ipad-display-watcher.c" \
  -o "$BIN_DIR/ipad-display-watcher" \
  -framework ApplicationServices \
  -framework CoreFoundation \
  -O2

if [[ ! -f "$CONFIG_FILE" ]]; then
  cat > "$CONFIG_FILE" <<'EOF'
# Known external monitors that should not trigger the iPad prompt.
# Format: vendor:model
# Find values with: ipad-display-watcher --list
19491:9571 # G4Q
EOF
fi

if [[ ${#KNOWN_MONITORS[@]} -gt 0 ]]; then
  for item in "${KNOWN_MONITORS[@]}"; do
    if [[ ! "$item" =~ ^[0-9]+:[0-9]+$ ]]; then
      echo "invalid monitor entry: $item (expected VENDOR:MODEL)" >&2
      exit 2
    fi
    if ! grep -Eq "^${item//:/:}([[:space:]#]|$)" "$CONFIG_FILE"; then
      printf '%s\n' "$item" >> "$CONFIG_FILE"
    fi
  done
fi

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$BIN_DIR/ipad-display-watcher</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key>
    <string>$HOME</string>
  </dict>
  <key>StandardOutPath</key>
  <string>$LOG_DIR/ipad-display-watcher.out.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/ipad-display-watcher.err.log</string>
</dict>
</plist>
EOF

plutil -lint "$PLIST" >/dev/null

if [[ "$START_SERVICE" -eq 1 ]]; then
  launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST"
  launchctl kickstart -k "gui/$(id -u)/$LABEL"
fi

echo "Installed ipad-display-watcher."
echo "Binary: $BIN_DIR/ipad-display-watcher"
echo "Config: $CONFIG_FILE"
echo "LaunchAgent: $PLIST"
echo "Log: $LOG_DIR/ipad-display-watcher.err.log"
