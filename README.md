# SiliconStats

A lightweight macOS menu bar app that displays real-time CPU temperature and load.

Built natively in Swift with no dependencies — reads thermal sensors directly from the SMC via IOKit and calculates CPU usage from Mach kernel APIs.

## Features

- **Menu bar stats** — CPU temperature and load percentage always visible in the top bar using SF Symbols
- **Floating overlay** — a draggable, always-on-top panel that stays visible over fullscreen apps and games
- **Launch at Login** — toggle from the dropdown menu
- **Apple Silicon & Intel** — auto-detects sensor type and data format
- **No Dock icon** — runs entirely as a menu bar accessory

## Requirements

- macOS 13+
- Swift 5.9+

## Build & Install

```bash
./build.sh
```

This compiles a release binary, packages it into `SiliconStats.app` with an icon, ad-hoc code signs it, and installs it to `/Applications/`. Launch it from Spotlight by searching "SiliconStats".

## Development

```bash
swift build
.build/debug/SiliconStats
```

## Temperature Note

SMC access for CPU temperature may require elevated privileges on some systems. If the temperature doesn't appear, try launching with `sudo`. CPU load percentage works without any special permissions.

## License

MIT
