# claude-linux-computer

Open-source Linux computer-use plugin for Claude Code.

Take screenshots, click, type, move the mouse, manage windows — all from Claude Code on Linux via X11. Claude's built-in `/computer` tool is Mac-only; this plugin brings the same capabilities to Linux.

## Requirements

- **Linux** with an X11 session
- **[Bun](https://bun.sh)** — the MCP server runs on Bun
- **xdotool** — click, type, key, mouse, and window operations
- **scrot** — screenshots
- **imagemagick** — image processing and grid overlays
- **tesseract-ocr** — OCR for `find_text` tool

## Quick Start

**1. Install system dependencies** (Debian/Ubuntu):

```sh
sudo apt install -y xdotool scrot imagemagick tesseract-ocr
```

**2. Install the plugin.**

Add the GitHub repo as a marketplace, then install:

```sh
claude plugin marketplace add https://github.com/Nige-l/claude-linux-computer
claude plugin install linux-computer
```

**3. Use the tools.** Ask Claude to take a screenshot, click a button, type text, or manage windows. The tools are available automatically once the plugin is installed.

### Alternative: local install from a clone

```sh
git clone https://github.com/Nige-l/claude-linux-computer.git
claude --plugin-dir ./claude-linux-computer
```

This loads the plugin for a single session without installing it globally.

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
| `find_text` | OCR the screen to locate text, returns center coordinates | `text`, `window` |
| `cursor_position` | Get current mouse cursor position | — |
| `grid_screenshot` | Screenshot with coordinate grid overlay | `window`, `spacing` |
| `computer_status` | Get display and system status | — |

## Skills

| Skill | Description |
|-------|-------------|
| `/linux-computer:status` | Check plugin health — display server, dependencies, screen resolution, visible windows |
| `/linux-computer:setup` | Guided installation of system dependencies with distro detection |
| `/linux-computer:find-and-click` | Locate a UI element by text label (OCR) and click on it |
| `/linux-computer:interact` | Interactive desktop session — observe screen and perform actions |

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
