# ColimaBar

A native macOS menu bar app for [Colima](https://github.com/abiosoft/colima) - the container runtime for macOS.

![ColimaBar Screenshot](docs/colimabar.png)

## Features

- Shows all Colima instances in the menu bar
- Start, Stop, and Restart each instance individually
- Open a shell into a running instance (via Terminal)
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

### First launch

ColimaBar is ad-hoc signed, not notarized by Apple, so on first launch macOS
shows an "unidentified developer" warning. Right-click the app in Applications
and choose **Open**, then confirm. You only need to do this once.

If macOS still refuses to open it, clear the download quarantine flag:

```
xattr -dr com.apple.quarantine /Applications/ColimaBar.app
```

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

Once running, ColimaBar appears in your menu bar. The icon reflects the
overall state of your instances:

| Icon | Meaning |
|------|---------|
| Filled box | At least one instance is running |
| Empty box | All instances are stopped |
| Box with arrow | An instance is starting or stopping |

Click the icon to open the menu. Each instance is a row (`●` running, `○`
stopped) that expands into its own submenu.

### Managing instances

Open an instance's submenu to see its details (status, arch, CPUs, memory,
disk) and act on it:

- **Start** / **Stop** the instance
- **Restart** a running instance
- **Open Shell** — launch Terminal and SSH into the running instance
- **Delete…** — permanently remove the instance and its data (asks for
  confirmation first)

When more than one instance exists, **Start All** and **Stop All** appear in
the main menu.

### Creating an instance

Choose **New Instance…** and fill in a name, CPU count, memory (GiB), and disk
size (GiB). ColimaBar creates it with `colima start` using those resources.

### Open Shell permissions

The first time you use **Open Shell**, macOS asks ColimaBar for permission to
control Terminal. Allow it. If it was previously denied, re-enable it under
System Settings › Privacy & Security › Automation › ColimaBar.

### Preferences

- **Refresh Interval** — how often status is polled (5 / 10 / 30 / 60 seconds).
  The choice is remembered across launches. Polling pauses while an instance is
  starting or stopping so transitions aren't interrupted.
- **Launch at Login** — start ColimaBar automatically when you log in.

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| N | New Instance |
| R | Refresh Status |
| Q | Quit |

## License

MIT License - see [LICENSE](LICENSE) for details.
