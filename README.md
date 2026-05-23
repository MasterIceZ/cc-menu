# cc-menu

A minimal macOS menu bar app that shows your Claude AI quota usage.

```
✽ 20% 5%
```

- First % — 5-hour session usage
- Second % — 7-day weekly usage

## Requirements

- macOS 13+
- Claude Code installed and logged in

## Install

```bash
brew tap MasterIceZ/tap
brew install --cask cc-menu
```

Launch **cc-menu** from Spotlight, then add it to **System Settings → General → Login Items** to start automatically at login.

## Menu

Click the menu bar item to see reset times, reconnect, open a new chat, or quit.

## Build from source

```bash
swift build
.build/debug/cc-menu
```

## License

MIT
