#!/usr/bin/env bash
set -euo pipefail

LABEL="com.hyy.sidecar-arranger"
SCRIPT_PATH="${BASH_SOURCE[0]:-}"
if [[ -n "$SCRIPT_PATH" && -f "$SCRIPT_PATH" ]]; then
  ROOT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
else
  ROOT_DIR="$(pwd)"
fi
RAW_BASE="${SIDECAR_ARRANGER_RAW_BASE:-${IPAD_DISPLAY_WATCHER_RAW_BASE:-https://raw.githubusercontent.com/hututuo/sidecar-arranger/main}}"
SRC_DIR="$HOME/.local/sidecar-arranger"
BIN_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config/sidecar-arranger"
CONFIG_FILE="$CONFIG_DIR/known-monitors.txt"
OLD_CONFIG_FILE="$HOME/.config/ipad-display-watcher/known-monitors.txt"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
OLD_PLIST="$HOME/Library/LaunchAgents/com.hyy.ipad-display-watcher.plist"
LOG_DIR="$HOME/Library/Logs"
START_SERVICE=1
KNOWN_MONITORS=()
TMP_DIR=""
SERVICE_STARTED=0

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
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/hututuo/sidecar-arranger/main/install.sh)"

Options:
  --known-monitor VENDOR:MODEL  Add an external monitor that should not prompt
  --no-start                    Build and install, but do not start LaunchAgent
  -h, --help                    Show this help

Examples:
  ./install.sh
  ./install.sh --known-monitor 19491:9571
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/hututuo/sidecar-arranger/main/install.sh)"
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

WATCHER_SOURCE="$(source_file sidecar-arranger.c)"
DIALOG_SOURCE="$(source_file sidecar-arranger-dialog.m)"

mkdir -p "$SRC_DIR" "$BIN_DIR" "$CONFIG_DIR" "$LOG_DIR" "$(dirname "$PLIST")"
install -m 0644 "$WATCHER_SOURCE" "$SRC_DIR/sidecar-arranger.c"
install -m 0644 "$DIALOG_SOURCE" "$SRC_DIR/sidecar-arranger-dialog.m"

clang "$SRC_DIR/sidecar-arranger-dialog.m" \
  -o "$BIN_DIR/sidecar-arranger-dialog" \
  -framework Cocoa \
  -O2

clang "$SRC_DIR/sidecar-arranger.c" \
  -o "$BIN_DIR/sidecar-arranger" \
  -framework ApplicationServices \
  -framework CoreFoundation \
  -O2

ln -sf "$BIN_DIR/sidecar-arranger" "$BIN_DIR/ipad-display-watcher"
ln -sf "$BIN_DIR/sidecar-arranger-dialog" "$BIN_DIR/ipad-dialog"

if [[ ! -f "$CONFIG_FILE" ]]; then
  if [[ -f "$OLD_CONFIG_FILE" ]]; then
    cp "$OLD_CONFIG_FILE" "$CONFIG_FILE"
  else
    cat > "$CONFIG_FILE" <<'EOF'
# Known external monitors that should not trigger the iPad prompt.
# Format: vendor:model
# Find values with: sidecar-arranger --list
19491:9571 # G4Q
EOF
  fi
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
    <string>$BIN_DIR/sidecar-arranger</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key>
    <string>$HOME</string>
    <key>SIDECAR_ARRANGER_DIALOG</key>
    <string>$BIN_DIR/sidecar-arranger-dialog</string>
  </dict>
  <key>StandardOutPath</key>
  <string>$LOG_DIR/sidecar-arranger.out.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/sidecar-arranger.err.log</string>
</dict>
</plist>
EOF

plutil -lint "$PLIST" >/dev/null
launchctl bootout "gui/$(id -u)" "$OLD_PLIST" >/dev/null 2>&1 || true
rm -f "$OLD_PLIST"

if [[ "$START_SERVICE" -eq 1 ]]; then
  launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST"
  launchctl kickstart -k "gui/$(id -u)/$LABEL"
  SERVICE_STARTED=1
fi

echo "Installed Sidecar Arranger."
echo "Binary: $BIN_DIR/sidecar-arranger"
echo "Config: $CONFIG_FILE"
echo "LaunchAgent: $PLIST"
echo "Log: $LOG_DIR/sidecar-arranger.err.log"

if [[ "$SERVICE_STARTED" -eq 1 ]] && command -v osascript >/dev/null; then
  /usr/bin/osascript <<'APPLESCRIPT' >/dev/null 2>&1 || true
display dialog "Sidecar Arranger 已安装并开启开机自启。\n\n连接 iPad 随航后，会弹出位置选择窗口。" buttons {"知道了"} default button "知道了" with title "Sidecar Arranger" with icon note
APPLESCRIPT
fi
