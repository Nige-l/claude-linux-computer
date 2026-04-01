---
name: interact
description: Interactive desktop session — take a screenshot, observe the screen, and perform actions the user requests. Use when the user says "look at my screen", "what's on screen", "help me with this window", or wants guided desktop interaction.
user-invocable: true
allowed-tools: [mcp__plugin_linux-computer_linux-computer__screenshot, mcp__plugin_linux-computer_linux-computer__grid_screenshot, mcp__plugin_linux-computer_linux-computer__find_text, mcp__plugin_linux-computer_linux-computer__cursor_position, mcp__plugin_linux-computer_linux-computer__click, mcp__plugin_linux-computer_linux-computer__type, mcp__plugin_linux-computer_linux-computer__key, mcp__plugin_linux-computer_linux-computer__mouse_move, mcp__plugin_linux-computer_linux-computer__scroll, mcp__plugin_linux-computer_linux-computer__find_window, mcp__plugin_linux-computer_linux-computer__focus_window, mcp__plugin_linux-computer_linux-computer__drag, mcp__plugin_linux-computer_linux-computer__computer_status]
---

# /linux-computer:interact

Start an interactive desktop session — observe the screen and help the user accomplish tasks.

## Steps

### 1. Observe

Take a `screenshot` to see the current state of the desktop. Describe what you see briefly.

### 2. Listen

Ask the user what they'd like to do, or if they already told you, proceed to act.

### 3. Act

For each action the user requests:

1. **Locate targets with `find_text`** before clicking. Never guess coordinates from a screenshot when text-based targeting is available.
2. **Perform the action** (click, type, key press, scroll, etc.).
3. **Take a screenshot** after the action to verify it worked and show the user the result.
4. **Report** what happened and what you see now.

### 4. Iterate

Continue observing and acting until the user is satisfied. Between actions, always screenshot to stay aware of screen state — things like popups, dialogs, or loading states may appear.

## Guidelines

- Always use `find_text` before clicking buttons, links, menu items, or any labeled UI element.
- Use `grid_screenshot` when you need to click something that doesn't have text (icons, blank areas, sliders).
- Use `cursor_position` to verify where the mouse is if a click seems to have missed.
- When typing into a field, click the field first (via `find_text` on its label), then `type`.
- For keyboard shortcuts, use `key` with combos like `ctrl+s`, `alt+Tab`, `super`.
- If an action fails or has unexpected results, screenshot and explain what happened rather than retrying blindly.
