# Sidecar Arranger

Sidecar Arranger is a tiny macOS helper for arranging an iPad Sidecar display.

When a new unknown external display appears, it shows a small local dialog asking where the iPad is relative to the built-in MacBook display: right, left, above, or below. It then applies that display arrangement.

It is intentionally lightweight: it only detects display metadata and sets display order. It does not watch your screen, inspect windows, read files, or send anything over the network.

## What It Does

- Polls macOS display state every 3 seconds.
- Ignores the built-in MacBook display.
- Ignores known external monitors.
- Prompts only when an unknown secondary display appears.
- Moves that display to the chosen side of the built-in display.
- Lets you ignore a non-iPad display from the dialog so it will not prompt again.
- Starts automatically at login through a user LaunchAgent.

## Privacy

Sidecar Arranger is a local-only native helper.

It reads only:

- active display IDs
- display sizes and positions
- built-in display status
- display vendor ID and model ID

It does not:

- capture screenshots
- inspect windows or apps
- read files or folders
- monitor keyboard, mouse, or clipboard input
- access camera or microphone
- make network requests at runtime

The install script downloads source files from GitHub only during installation. Runtime logs stay local:

```sh
~/Library/Logs/sidecar-arranger.err.log
~/Library/Logs/sidecar-arranger.out.log
```

## Install

One-line install:

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/hututuo/sidecar-arranger/main/install.sh)"
```

The installer downloads the source files, compiles two small native binaries, writes the user LaunchAgent, and starts the watcher.

If you prefer to inspect the repository first:

```sh
git clone https://github.com/hututuo/sidecar-arranger.git
cd sidecar-arranger
./install.sh
```

## Homebrew

Install and start:

```sh
brew install hututuo/tap/sidecar-arranger && brew services start hututuo/tap/sidecar-arranger
```

Homebrew will automatically add the `hututuo/tap` tap when installing from this command.

## Installed Paths

| File | Path |
|---|---|
| Main source | `~/.local/sidecar-arranger/sidecar-arranger.c` |
| Dialog source | `~/.local/sidecar-arranger/sidecar-arranger-dialog.m` |
| Main binary | `~/.local/bin/sidecar-arranger` |
| Dialog binary | `~/.local/bin/sidecar-arranger-dialog` |
| Compatibility command | `~/.local/bin/ipad-display-watcher` |
| Compatibility dialog | `~/.local/bin/ipad-dialog` |
| LaunchAgent | `~/Library/LaunchAgents/com.hyy.sidecar-arranger.plist` |
| Known monitor config | `~/.config/sidecar-arranger/known-monitors.txt` |
| Error log | `~/Library/Logs/sidecar-arranger.err.log` |

## Ignore a Display

When the dialog appears, choose:

```text
忽略此显示器，以后不再弹窗
```

Sidecar Arranger will add the current display's `vendor:model` pair to:

```sh
~/.config/sidecar-arranger/known-monitors.txt
```

After that, the same external monitor will be ignored automatically.

You can also add a known monitor manually:

```sh
echo '12345:67890 # Desk monitor' >> ~/.config/sidecar-arranger/known-monitors.txt
```

Find display IDs with:

```sh
sidecar-arranger --list
```

## Commands

List displays:

```sh
sidecar-arranger --list
```

Move the iPad manually:

```sh
sidecar-arranger left
sidecar-arranger right
sidecar-arranger above
sidecar-arranger below
```

Restart the LaunchAgent:

```sh
launchctl kickstart -k gui/$(id -u)/com.hyy.sidecar-arranger
```

Stop it:

```sh
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.hyy.sidecar-arranger.plist
```

Start it again:

```sh
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.hyy.sidecar-arranger.plist
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
clang sidecar-arranger-dialog.m \
  -o sidecar-arranger-dialog \
  -framework Cocoa \
  -O2

clang sidecar-arranger.c \
  -o sidecar-arranger \
  -framework ApplicationServices \
  -framework CoreFoundation \
  -O2
```

## Notes

- Sidecar Arranger is intended for MacBooks because it anchors the arrangement to the built-in display.
- The dialog supports cancel. Canceling will not move the display and will not ignore it.
- The old `ipad-display-watcher` command is kept as a compatibility symlink by the installer.
