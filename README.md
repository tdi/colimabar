# ColimaBar

A native macOS menu bar app for [Colima](https://github.com/abiosoft/colima) - the container runtime for macOS.

![ColimaBar Screenshot](docs/colimabar.png)

## Features

- Shows all Colima instances in the menu bar
- Start, Stop, and Restart each instance individually
- Start All / Stop All when running multiple instances
- Create new instances (name, CPUs, memory, disk) and delete existing ones
- View instance details (arch, CPUs, memory, disk)
- Auto-refresh with a configurable interval (5/10/30/60 seconds)
- Launch at login
- Clear status and error reporting (e.g. when Colima is not installed)
- Lightweight, native Swift implementation

## Requirements

- macOS 13.0+
- [Colima](https://github.com/abiosoft/colima) installed (`brew install colima`)

## Installation

### From DMG

Download the latest release DMG and drag ColimaBar to your Applications folder.

### Build from Source

```bash
git clone https://github.com/tdi/colimabar.git
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
- View all Colima instances
- Expand an instance submenu for details and controls (Start, Stop, Restart, Delete)
- Start All / Stop All instances
- Create a new instance
- Set the auto-refresh interval
- Toggle Launch at Login
- Refresh status manually
- Quit the app

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| N | New Instance |
| R | Refresh Status |
| Q | Quit |

## License

MIT License - see [LICENSE](LICENSE) for details.
