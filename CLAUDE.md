# Linux Computer-Use Plugin

Desktop automation for Linux via X11. You have 13 tools for screenshots, clicking, typing, keyboard input, mouse movement, window management, OCR text search, and cursor tracking.

## Tool quick reference

| Tool | Purpose |
|------|---------|
| `screenshot` | Capture screen or window — returns image inline |
| `grid_screenshot` | Screenshot with coordinate grid overlay — use when you need precise coordinates |
| `find_text` | OCR the screen to locate text — returns center (x, y) coordinates you can click |
| `cursor_position` | Get current mouse cursor position |
| `click` | Click at (x, y) coordinates |
| `type` | Type text via keyboard |
| `key` | Press key combos (e.g. `ctrl+c`, `alt+F4`, `Return`) |
| `mouse_move` | Move cursor to (x, y) |
| `drag` | Drag from one point to another |
| `scroll` | Scroll at (x, y) in a direction |
| `find_window` | Find windows by name pattern |
| `focus_window` | Activate a window |
| `computer_status` | Display/dependency health check |

## How to click on UI elements accurately

**Do NOT guess coordinates from a screenshot.** Use this workflow instead:

1. **`find_text`** to locate the element by its label text. This returns the exact center coordinates.
2. **`click`** at the coordinates returned by `find_text`.

Example: to click a "Save" button, call `find_text` with `text: "Save"`, then `click` at the returned `x, y`.

If `find_text` doesn't find the element (icons without text, custom-rendered UI), fall back to:
1. **`grid_screenshot`** to get a screenshot with coordinate gridlines.
2. Read the grid numbers to estimate coordinates.
3. **`click`** at the estimated position.

As a last resort, use a regular `screenshot` and estimate coordinates — but this is the least accurate method.

## Coordinate system

- Coordinates are in **screen pixels** (absolute) unless `--window` is used, which makes them **window-relative**.
- Multi-monitor setups: coordinates span the full virtual screen. Monitor 2 starts where monitor 1 ends (e.g. at x=1920 for two side-by-side 1920px monitors).
- Use `computer_status` to check resolution and `cursor_position` to verify where the mouse is.

## Window targeting

Most tools accept an optional `window` parameter (name pattern). When provided:
- The window is focused first, then the action is performed with window-relative coordinates.
- Pattern matching is case-sensitive substring match via `xdotool search --name`.

When omitted, actions use absolute screen coordinates on whatever is currently focused.

## Common patterns

**Open an app and interact with it:**
1. Launch via `key` (`super`) or shell command
2. Wait a moment for the window to appear
3. `find_window` / `focus_window` to target it
4. `find_text` to locate UI elements, then `click`

**Fill in a form:**
1. `find_text` to locate the field label
2. `click` on or near the field
3. `type` the value
4. `key` with `Tab` to move to next field

**Navigate browser UI:**
1. `find_text` to locate bookmarks, tabs, or buttons by their text
2. For the address bar: `key` with `ctrl+l`, then `type` the URL, then `key` with `Return`

## Dependencies

Required: `xdotool`, `scrot`, `imagemagick`. Optional: `tesseract-ocr` (for `find_text`).

If a tool fails with a missing dependency error, suggest running `/linux-computer:setup`.
