---
name: status
description: Check Linux computer-use tool status — display server, dependencies, screen resolution, visible windows. Use when user asks about computer tool setup or display issues.
user-invocable: true
allowed-tools: [Bash, Read]
---

# /computer:status

Check the health and readiness of the Linux computer-use plugin.

## Steps

1. Run the status check script:

```bash
"$CLAUDE_PLUGIN_ROOT/bin/linux-computer.sh" status
```

If `CLAUDE_PLUGIN_ROOT` is not set, resolve the script path relative to this skill file (two directories up: `../../bin/linux-computer.sh`).

2. Present the output to the user in a readable format. The output includes:
   - Display server info (DISPLAY variable, resolution)
   - Installed dependencies (xdotool, scrot, imagemagick)
   - Missing dependencies
   - Active windows

3. Check `XDG_SESSION_TYPE`:

```bash
echo "$XDG_SESSION_TYPE"
```

- If the value is `wayland`, warn the user: "You are running a Wayland session. This plugin requires X11 for full functionality. Some operations may work under XWayland, but for best results log out and select an X11/Xorg session from your display manager."

4. If any dependencies are missing, suggest running `/computer:setup` to install them.
