---
name: setup
description: Guide setup of Linux computer-use dependencies — detect distro, install xdotool, scrot, imagemagick. Use when user asks to install or configure the computer tool, or when dependencies are missing.
user-invocable: true
allowed-tools: [Bash, Read]
---

# /linux-computer:setup

Guide the user through installing dependencies for the Linux computer-use plugin.

## Steps

### 1. Check session type

```bash
echo "$XDG_SESSION_TYPE"
```

- If **wayland**: Explain that xdotool requires X11 for full functionality. Offer two options:
  1. Log out and select an X11/Xorg session from the display manager login screen
  2. Continue anyway — XWayland may work for some operations (screenshot, basic clicks) but keyboard and window management may be unreliable
- If **x11** or **tty**: Proceed normally.

### 2. Check which dependencies are already installed

Run each check and note which are missing:

```bash
command -v xdotool && xdotool --version
command -v scrot && scrot --version
command -v convert && convert --version | head -1
```

- **xdotool** — required for click, type, key, mouse, and window operations
- **scrot** — required for screenshots
- **imagemagick** (provides `convert`) — optional, used for image processing

### 3. Detect package manager and install missing packages

Check which package manager is available:

| Distro | Check | Install command |
|--------|-------|----------------|
| Debian/Ubuntu | `command -v apt` | `sudo apt update && sudo apt install -y xdotool scrot imagemagick` |
| Fedora | `command -v dnf` | `sudo dnf install -y xdotool scrot ImageMagick` |
| Arch | `command -v pacman` | `sudo pacman -S --noconfirm xdotool scrot imagemagick` |
| openSUSE | `command -v zypper` | `sudo zypper install -y xdotool scrot ImageMagick` |

Only include missing packages in the install command. Tell the user the exact command and ask for confirmation before running it (since it requires sudo).

### 4. Verify installation

After installation, re-run the dependency checks from step 2 to confirm everything is working. If all required deps are present, report success.

Suggest running `/linux-computer:status` for a full health check.
