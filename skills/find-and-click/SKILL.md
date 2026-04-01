---
name: find-and-click
description: Find a UI element by its text label using OCR and click on it. Use when the user says "click on X" or "press the X button" and you need to locate it on screen first.
user-invocable: true
allowed-tools: [mcp__plugin_linux-computer_linux-computer__find_text, mcp__plugin_linux-computer_linux-computer__click, mcp__plugin_linux-computer_linux-computer__screenshot, mcp__plugin_linux-computer_linux-computer__grid_screenshot, mcp__plugin_linux-computer_linux-computer__focus_window]
---

# /linux-computer:find-and-click

Locate a UI element by its visible text and click on it.

## Input

The user provides:
- The text label to find (e.g. "Save", "OK", "File", a menu item, a bookmark name)
- Optionally, a window to search in

## Steps

### 1. Focus the target window (if specified)

If the user mentioned a specific app or window, use `focus_window` to bring it to the front first.

### 2. Find the text with OCR

Call `find_text` with the target text. If a window was specified, pass the `window` parameter.

### 3. Handle results

**If found (one match):** Click at the returned `x, y` coordinates immediately.

**If found (multiple matches):** Take a `screenshot` and show it to the user. List the matches with their coordinates and ask which one to click, unless the user's intent is unambiguous (e.g. there's only one "Save" button visible in the active area).

**If not found:**
1. Take a `grid_screenshot` and show it to the user.
2. Tell them the text wasn't found by OCR.
3. Ask them to point out where the element is, or try alternate text (OCR may read the label slightly differently).

### 4. Confirm the click

After clicking, take a `screenshot` to show the result so the user can verify the click landed correctly.
