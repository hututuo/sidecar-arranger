# iPad Display Watcher

`ipad-display-watcher` is a small macOS helper for people who use an iPad as a Sidecar display. When a new unknown external display appears, it shows a compact dialog asking whether the iPad is on the right, left, above, or below the built-in MacBook display, then applies the matching display arrangement.

It is designed for a MacBook workflow where your regular external monitors are ignored and only the iPad/Sidecar display triggers the picker.

## Privacy

The watcher does not capture screenshots, inspect windows, read files, monitor keyboard input, access camera or microphone, or send network requests.

It only reads local CoreGraphics display metadata:

- active display IDs
- display geometry
- built-in display status
- vendor ID and model ID

Logs are local and live at:

```sh
~/Library/Logs/ipad-display-watcher.err.log
~/Library/Logs/ipad-display-watcher.out.log
```

## Install

One-line install:

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/hututuo/ipad-display-watcher/main/install.sh)"
```

This downloads the installer, pulls the source files, compiles the two native
binaries, writes the user LaunchAgent, and starts the watcher.

If you prefer to inspect the repository first:

```sh
git clone https://github.com/hututuo/ipad-display-watcher.git
cd ipad-display-watcher
./install.sh
```

Installed paths:

| File | Path |
|---|---|
| Main source | `~/.local/ipad-display-watcher/ipad-display-watcher.c` |
| Dialog source | `~/.local/ipad-display-watcher/ipad-dialog.m` |
| Main binary | `~/.local/bin/ipad-display-watcher` |
| Dialog binary | `~/.local/bin/ipad-dialog` |
| LaunchAgent | `~/Library/LaunchAgents/com.hyy.ipad-display-watcher.plist` |
| Known monitor config | `~/.config/ipad-display-watcher/known-monitors.txt` |
| Error log | `~/Library/Logs/ipad-display-watcher.err.log` |

## Known Monitors

Known external monitors do not trigger the iPad dialog. The default build already ignores:

```text
19491:9571 # G4Q
```

To find your monitor IDs:

```sh
ipad-display-watcher --list
```

Add a known monitor:

```sh
echo '12345:67890 # Desk monitor' >> ~/.config/ipad-display-watcher/known-monitors.txt
```

Or during install:

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/hututuo/ipad-display-watcher/main/install.sh)" -- --known-monitor 12345:67890
```

## Commands

List displays:

```sh
ipad-display-watcher --list
```

Move the iPad manually:

```sh
ipad-display-watcher left
ipad-display-watcher right
ipad-display-watcher above
ipad-display-watcher below
```

Restart the LaunchAgent:

```sh
launchctl kickstart -k gui/$(id -u)/com.hyy.ipad-display-watcher
```

Stop it:

```sh
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.hyy.ipad-display-watcher.plist
```

Start it again:

```sh
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.hyy.ipad-display-watcher.plist
```

Uninstall:

```sh
./uninstall.sh
```

Remove config too:

```sh
./uninstall.sh --purge-config
```

## Build Manually

```sh
clang ~/.local/ipad-display-watcher/ipad-dialog.m \
  -o ~/.local/bin/ipad-dialog \
  -framework Cocoa \
  -O2

clang ~/.local/ipad-display-watcher/ipad-display-watcher.c \
  -o ~/.local/bin/ipad-display-watcher \
  -framework ApplicationServices \
  -framework CoreFoundation \
  -O2
```

## Notes

- The dialog supports a real cancel action. Canceling will not move the display and will not prompt again until the display disconnects and reconnects.
- The watcher is intended for MacBooks because it anchors the arrangement to the built-in display.
- If an unknown non-iPad external monitor triggers the dialog, add that monitor to `known-monitors.txt`.
