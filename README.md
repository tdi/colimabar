# ColimaBar

A native macOS menu bar app for [Colima](https://github.com/abiosoft/colima) - the container runtime for macOS.

## Features

- Shows Colima status in the menu bar
- Start/Stop Colima with a click
- Auto-refreshes status every 5 seconds
- Lightweight, native Swift implementation

## Requirements

- macOS 13.0+
- [Colima](https://github.com/abiosoft/colima) installed (`brew install colima`)

## Installation

### From DMG

Download the latest release DMG and drag ColimaBar to your Applications folder.

### Build from Source

```bash
git clone https://github.com/yourusername/colimabar.git
cd colimabar
./build-app.sh
open ColimaBar.app
```

To create a DMG:

```bash
./build-dmg.sh
```

## Usage

Once running, ColimaBar appears in your menu bar:

- **Filled box icon** - Colima is running
- **Empty box icon** - Colima is stopped

Click the icon to:
- View current status
- Start or Stop Colima
- Refresh status manually
- Quit the app

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| S | Start Colima |
| X | Stop Colima |
| R | Refresh Status |
| Q | Quit |

## License

MIT License - see [LICENSE](LICENSE) for details.
