# claude-linux-computer

Open-source Linux computer-use plugin for Claude Code.

Take screenshots, click, type, move the mouse, manage windows — all from Claude Code on Linux via X11. Claude's built-in `/computer` tool is Mac-only; this plugin brings the same capabilities to Linux.

## Requirements

- **Linux** with an X11 session
- **[Bun](https://bun.sh)** — the MCP server runs on Bun
- **xdotool** — click, type, key, mouse, and window operations
- **scrot** — screenshots
- **imagemagick** (optional) — image processing

## Installation

Install the plugin in Claude Code:

```
/plugin install /path/to/claude-linux-computer
```

Or from a git URL:

```
/plugin install https://github.com/Nige-l/claude-linux-computer
```

## Quick Start

**1. Install system dependencies.**

Run the setup skill inside Claude Code:

```
/linux-computer:setup
```

Or install manually (Debian/Ubuntu):

```sh
sudo apt install -y xdotool scrot imagemagick
```

**2. Install the plugin** (see Installation above).

**3. Use the tools.** Ask Claude to take a screenshot, click a button, type text, or manage windows. The tools are available automatically once the plugin is installed.

## Tools

| Tool | Description | Key Parameters |
|------|-------------|----------------|
| `screenshot` | Capture the screen or a specific window, returns image inline | `window` (optional name pattern) |
| `click` | Click at screen coordinates | `x`, `y`, `button` (left/middle/right), `window` |
| `type` | Type text with keyboard | `text`, `window` |
| `key` | Press a key or key combination (e.g. `ctrl+c`, `alt+F4`) | `key`, `window` |
| `mouse_move` | Move the mouse cursor | `x`, `y`, `window` |
| `drag` | Drag from one point to another | `start_x`, `start_y`, `end_x`, `end_y`, `window` |
| `scroll` | Scroll at screen coordinates | `x`, `y`, `direction` (up/down/left/right), `clicks`, `window` |
| `find_window` | Find windows matching a name pattern | `pattern` |
| `focus_window` | Focus (activate) a window by name or ID | `target` |
| `computer_status` | Get display and system status | — |

## Skills

| Skill | Description |
|-------|-------------|
| `/linux-computer:status` | Check plugin health — display server, dependencies, screen resolution, visible windows |
| `/linux-computer:setup` | Guided installation of system dependencies with distro detection |

## Wayland

This plugin targets X11. On Wayland sessions:

- Some operations may work through **XWayland** (screenshots, basic mouse clicks)
- Keyboard input and window management may be unreliable
- For best results, log out and select an **X11/Xorg session** from your display manager

Full Wayland support is planned for a future release.

## Contributing

Contributions are welcome. Open an issue or submit a pull request.

## License

[MIT](LICENSE)
