#!/usr/bin/env bash
# linux-computer.sh — Standalone Linux computer-use tool for AI agents
# Provides screenshot, click, type, key, scroll, and window management
# via X11/XWayland using xdotool, scrot, and ImageMagick.
set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

OUTPUT_DIR="/tmp/claude_linux_computer"
LOG_FILE="$OUTPUT_DIR/actions.log"
DISPLAY="${DISPLAY:-:0}"
DESKTOP_LOCK_FILE="/tmp/claude_linux_computer_desktop.lock"
DESKTOP_LOCK_FD=""   # set once per process; re-entrant callers reuse it

# Global defaults — must be initialized before any function calls (set -u safe)
DRY_RUN=false
JSON_OUTPUT="${JSON_OUTPUT:-false}"

# ---------------------------------------------------------------------------
# Session type warning
# ---------------------------------------------------------------------------

if [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
    printf 'Warning: XDG_SESSION_TYPE=wayland detected. xdotool may not work correctly.\n' >&2
    printf 'Consider running under X11, or ensure XWayland is available.\n' >&2
fi

# ---------------------------------------------------------------------------
# Color detection & print helpers
# ---------------------------------------------------------------------------

if [[ "${JSON_OUTPUT}" == "true" || -n "${NO_COLOR:-}" || ! -t 1 ]]; then
    RED="" GREEN="" YELLOW="" CYAN="" BOLD="" DIM="" RESET=""
else
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    DIM='\033[2m'
    RESET='\033[0m'
fi

ok() {
    [[ "${JSON_OUTPUT}" == "true" ]] && return 0
    printf "  ${GREEN}✓${RESET} %s\n" "$*"
}

err() {
    if [[ "${JSON_OUTPUT}" == "true" || -z "${RED}" ]]; then
        printf "  ✗ %s\n" "$*" >&2
    else
        printf "  ${RED}✗${RESET} %s\n" "$*" >&2
    fi
}

warn() {
    [[ "${JSON_OUTPUT}" == "true" ]] && return 0
    printf "  ${YELLOW}!${RESET} %s\n" "$*"
}

info() {
    [[ "${JSON_OUTPUT}" == "true" ]] && return 0
    printf "  ${CYAN}%s${RESET}\n" "$*"
}

bold() {
    [[ "${JSON_OUTPUT}" == "true" ]] && return 0
    printf "  ${BOLD}%s${RESET}\n" "$*"
}

dim() {
    [[ "${JSON_OUTPUT}" == "true" ]] && return 0
    printf "  ${DIM}%s${RESET}\n" "$*"
}

# ---------------------------------------------------------------------------
# JSON helpers
# ---------------------------------------------------------------------------

json_str() {
    local s="$1"
    s="${s//\\/\\\\}"   # \ -> \\
    s="${s//\"/\\\"}"   # " -> \"
    s="${s//$'\n'/\\n}" # newline -> \n
    s="${s//$'\r'/\\r}" # carriage return -> \r
    s="${s//$'\t'/\\t}" # tab -> \t
    s="${s//$'\b'/\\b}" # backspace -> \b
    s="${s//$'\f'/\\f}" # form feed -> \f
    # Strip remaining control chars (0x00-0x1f except those already handled)
    s=$(printf '%s' "$s" | tr -d '\000-\010\013\016-\037')
    printf '%s' "$s"
}

# Emit a JSON result object. Usage: json_result "ok" "message text"
json_result() {
    local status="$1" message="$2"
    printf '{"status":"%s","message":"%s"}\n' "$status" "$(json_str "$message")"
}

# Emit a JSON object with an arbitrary key. Usage: json_kv "path" "/tmp/foo.png"
json_kv() {
    local key="$1" value="$2"
    printf '{"%s":"%s"}\n' "$key" "$(json_str "$value")"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

ensure_dirs() {
    mkdir -p "$OUTPUT_DIR"
}

log_action() {
    local action="$1"
    local detail="${2:-}"
    ensure_dirs
    printf "[%s] %s%s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$action" "${detail:+ — $detail}" >> "$LOG_FILE"
}

require_xdotool() {
    if ! command -v xdotool &>/dev/null; then
        err "xdotool not found in PATH. Install with: sudo apt install xdotool"
        exit 1
    fi
}

require_scrot() {
    if ! command -v scrot &>/dev/null; then
        err "scrot not found in PATH. Install with: sudo apt install scrot"
        exit 1
    fi
}

require_import() {
    if ! command -v import &>/dev/null; then
        err "ImageMagick 'import' not found. Install with: sudo apt install imagemagick"
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Window helpers
# ---------------------------------------------------------------------------

# Find window ID by name pattern.
# When multiple matches exist, selects the one with the smallest height.
# Prints window ID to stdout. Returns exit 1 if none found.
find_window_id() {
    local pattern="$1"
    require_xdotool

    local ids
    ids=$(xdotool search --name "$pattern" 2>/dev/null || true)

    if [[ -z "$ids" ]]; then
        return 1
    fi

    # If only one window, return it directly.
    local count
    count=$(printf '%s\n' "$ids" | wc -l)
    if [[ "$count" -eq 1 ]]; then
        printf '%s' "$ids"
        return 0
    fi

    # Multiple windows: prefer the largest (by area) visible window.
    # Helper/tooltip windows are typically tiny (e.g. 10x10); the real
    # application window is almost always the biggest match.
    local best_id="" best_area=0
    while IFS= read -r wid; do
        [[ -z "$wid" ]] && continue
        local geom w h area
        geom=$(DISPLAY="$DISPLAY" xdotool getwindowgeometry "$wid" 2>/dev/null || true)
        w=$(printf '%s' "$geom" | grep -oP 'Geometry:\s*\K\d+(?=x)' || true)
        h=$(printf '%s' "$geom" | grep -oP 'Geometry:\s*\d+x\K\d+' || true)
        if [[ -n "$w" && -n "$h" ]]; then
            area=$(( w * h ))
            if [[ "$area" -gt "$best_area" ]]; then
                best_area="$area"
                best_id="$wid"
            fi
        fi
    done <<< "$ids"

    if [[ -n "$best_id" ]]; then
        printf '%s' "$best_id"
    else
        # Fallback: first match if geometry read failed for all windows
        printf '%s' "$ids" | head -1
    fi
}

# Resolve window: if looks like a numeric ID, use it directly; otherwise search by name.
resolve_window() {
    local id_or_name="$1"
    if [[ "$id_or_name" =~ ^[0-9]+$ ]]; then
        printf '%s' "$id_or_name"
    else
        local id
        id=$(find_window_id "$id_or_name") || {
            err "No window found matching: $id_or_name"
            exit 1
        }
        printf '%s' "$id"
    fi
}

# Get window title from ID
get_window_name() {
    local wid="$1"
    xdotool getwindowname "$wid" 2>/dev/null || printf "(unknown)"
}

# Parse --window <pattern>, --button <N>, and --dry-run flags from args.
# Sets globals: OPT_WINDOW, OPT_BUTTON, DRY_RUN. Remaining positional args in POSITIONAL.
parse_action_flags() {
    OPT_WINDOW=""
    OPT_BUTTON=1
    DRY_RUN=false
    POSITIONAL=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --window)
                shift
                OPT_WINDOW="${1:?--window requires a value}"
                ;;
            --window=*)
                OPT_WINDOW="${1#--window=}"
                ;;
            --button)
                shift
                OPT_BUTTON="${1:?--button requires a value}"
                ;;
            --button=*)
                OPT_BUTTON="${1#--button=}"
                ;;
            --dry-run)
                DRY_RUN=true
                ;;
            *)
                POSITIONAL+=("$1")
                ;;
        esac
        shift
    done
}

# Focus a window, with a short settling delay.
do_focus() {
    local wid="$1"
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[dry-run] Would focus window $wid"
        return 0
    fi
    xdotool windowfocus --sync "$wid" 2>/dev/null || xdotool windowfocus "$wid" 2>/dev/null
    # 100ms for window manager to process the focus
    sleep 0.1
}

# ---------------------------------------------------------------------------
# acquire_desktop_lock — flock-based desktop exclusivity lock.
# Re-entrant: if this process already holds the lock, this is a no-op.
# On contention: waits up to 10 seconds then fails with a clear error.
# The lock is held until the process exits (FD closed by OS).
# ---------------------------------------------------------------------------

acquire_desktop_lock() {
    [[ -n "$DESKTOP_LOCK_FD" ]] && return 0

    ensure_dirs

    # Safe: DESKTOP_LOCK_FILE is a hardcoded constant, not user input.
    eval "exec {DESKTOP_LOCK_FD}>\"$DESKTOP_LOCK_FILE\""

    if ! flock -w 10 "$DESKTOP_LOCK_FD" 2>/dev/null; then
        local holder_pid=""
        if command -v lsof &>/dev/null; then
            holder_pid=$(lsof -t "$DESKTOP_LOCK_FILE" 2>/dev/null | head -1 || true)
        fi
        if [[ -z "$holder_pid" ]]; then
            holder_pid=$(fuser "$DESKTOP_LOCK_FILE" 2>/dev/null | tr -s ' ' | sed 's/^ //' | awk '{print $1}' || true)
        fi
        if [[ -n "$holder_pid" ]]; then
            err "Desktop locked by PID $holder_pid. Another agent is using the display. Wait or check for stuck processes."
        else
            err "Desktop lock timeout after 10s. Another agent is using the display. Wait or check for stuck processes."
        fi
        eval "exec {DESKTOP_LOCK_FD}>&-"
        DESKTOP_LOCK_FD=""
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# lock-status — show desktop lock state
# ---------------------------------------------------------------------------

cmd_lock_status() {
    ensure_dirs

    printf "Desktop lock file: %s\n" "$DESKTOP_LOCK_FILE"

    if [[ ! -f "$DESKTOP_LOCK_FILE" ]]; then
        printf "Status: unlocked (lock file does not exist)\n"
        return 0
    fi

    local holder_pids=""
    if command -v lsof &>/dev/null; then
        holder_pids=$(lsof -t "$DESKTOP_LOCK_FILE" 2>/dev/null | tr '\n' ' ' | sed 's/ $//' || true)
    fi
    if [[ -z "$holder_pids" ]] && command -v fuser &>/dev/null; then
        holder_pids=$(fuser "$DESKTOP_LOCK_FILE" 2>/dev/null | tr -s ' ' | sed 's/^ //' || true)
    fi

    if [[ -z "$holder_pids" ]]; then
        printf "Status: unlocked (no processes holding lock)\n"
        return 0
    fi

    printf "Status: LOCKED\n"
    printf "Holder PID(s): %s\n" "$holder_pids"

    for pid in $holder_pids; do
        if [[ -f "/proc/$pid/stat" ]]; then
            local start_ticks elapsed_secs cmd_name uptime_secs clk_tck
            clk_tck=$(getconf CLK_TCK 2>/dev/null || printf "100")
            start_ticks=$(awk '{print $22}' /proc/"$pid"/stat 2>/dev/null || printf "0")
            uptime_secs=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || printf "0")
            local start_secs=$(( start_ticks / clk_tck ))
            local held_secs=$(( uptime_secs - start_secs ))
            cmd_name=$(cat /proc/"$pid"/comm 2>/dev/null || printf "unknown")
            printf "  PID %s: %s (process started ~%ds ago)\n" "$pid" "$cmd_name" "$held_secs"
        fi
    done
}

# ---------------------------------------------------------------------------
# screenshot [--window <pattern>] [--output <path>]
# ---------------------------------------------------------------------------

cmd_screenshot() {
    acquire_desktop_lock
    local args=("$@")
    OPT_WINDOW=""
    OPT_OUTPUT=""
    DRY_RUN=false

    while [[ ${#args[@]} -gt 0 ]]; do
        case "${args[0]}" in
            --window)
                OPT_WINDOW="${args[1]:?--window requires a value}"
                args=("${args[@]:2}")
                ;;
            --window=*)
                OPT_WINDOW="${args[0]#--window=}"
                args=("${args[@]:1}")
                ;;
            --output)
                OPT_OUTPUT="${args[1]:?--output requires a value}"
                args=("${args[@]:2}")
                ;;
            --output=*)
                OPT_OUTPUT="${args[0]#--output=}"
                args=("${args[@]:1}")
                ;;
            --dry-run)
                DRY_RUN=true
                args=("${args[@]:1}")
                ;;
            *)
                args=("${args[@]:1}")
                ;;
        esac
    done

    ensure_dirs

    local ts
    ts="$(date +%Y%m%d_%H%M%S_%N | cut -c1-20)"
    local out_path="${OPT_OUTPUT:-$OUTPUT_DIR/screenshot_${ts}.png}"

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[dry-run] Would capture screenshot to: $out_path"
        if [[ "$JSON_OUTPUT" == "true" ]]; then
            json_kv "path" "$out_path"
        else
            printf '%s\n' "$out_path"
        fi
        return 0
    fi

    if [[ -n "$OPT_WINDOW" ]]; then
        require_import

        local wid
        wid=$(find_window_id "$OPT_WINDOW") || {
            err "No window found matching: $OPT_WINDOW"
            exit 1
        }
        local wname
        wname=$(get_window_name "$wid")
        info "Capturing window: $wname (ID $wid)" >&2

        DISPLAY="$DISPLAY" import -window "$wid" "$out_path" 2>/dev/null || {
            err "import failed for window $wid — window may be hidden or minimised"
            exit 1
        }
    else
        require_scrot

        DISPLAY="$DISPLAY" scrot "$out_path" 2>/dev/null || {
            err "scrot failed — is DISPLAY=$DISPLAY accessible?"
            exit 1
        }
    fi

    log_action "screenshot" "$out_path"

    if [[ "$JSON_OUTPUT" == "true" ]]; then
        json_kv "path" "$out_path"
    else
        printf '%s\n' "$out_path"
    fi
}

# ---------------------------------------------------------------------------
# find-window <name_pattern>
# ---------------------------------------------------------------------------

cmd_find_window() {
    local pattern="${1:-}"
    if [[ -z "$pattern" ]]; then
        err "Usage: linux-computer find-window <name_pattern>"
        exit 1
    fi

    require_xdotool

    local ids
    ids=$(xdotool search --name "$pattern" 2>/dev/null || true)

    if [[ -z "$ids" ]]; then
        err "No windows found matching: $pattern"
        exit 1
    fi

    if [[ "$JSON_OUTPUT" == "true" ]]; then
        local first=true
        printf '['
        while IFS= read -r wid; do
            [[ -z "$wid" ]] && continue
            local wname geometry
            wname=$(get_window_name "$wid")
            geometry=$(xdotool getwindowgeometry "$wid" 2>/dev/null || printf "")
            local pos_x pos_y width height
            pos_x=$(printf '%s' "$geometry" | grep -oP 'Position:\s*\K\d+' | head -1 || printf "0")
            pos_y=$(printf '%s' "$geometry" | grep -oP 'Position:\s*\d+,\K\d+' || printf "0")
            width=$(printf '%s' "$geometry" | grep -oP 'Geometry:\s*\K\d+' || printf "0")
            height=$(printf '%s' "$geometry" | grep -oP 'Geometry:\s*\d+x\K\d+' || printf "0")
            [[ "$first" == "true" ]] || printf ','
            first=false
            printf '{"id":"%s","name":"%s","x":%s,"y":%s,"width":%s,"height":%s}' \
                "$wid" "$(json_str "$wname")" "$pos_x" "$pos_y" "$width" "$height"
        done <<< "$ids"
        printf ']\n'
    else
        while IFS= read -r wid; do
            [[ -z "$wid" ]] && continue
            local wname geometry
            wname=$(get_window_name "$wid")
            geometry=$(xdotool getwindowgeometry "$wid" 2>/dev/null || printf "(geometry unavailable)")
            printf "Window ID: %s\n" "$wid"
            printf "  Name:     %s\n" "$wname"
            printf "  Geometry: %s\n" "$(printf '%s' "$geometry" | grep -i 'geometry\|position\|size' | tr -s ' ' | sed 's/^ //')"
            printf "\n"
        done <<< "$ids"
    fi

    log_action "find-window" "$pattern"
}

# ---------------------------------------------------------------------------
# focus <window_id_or_name>
# ---------------------------------------------------------------------------

cmd_focus() {
    acquire_desktop_lock
    parse_action_flags "$@"
    local target="${POSITIONAL[0]:-}"

    if [[ -z "$target" ]]; then
        err "Usage: linux-computer focus <window_id_or_name>"
        exit 1
    fi

    require_xdotool

    local wid
    wid=$(resolve_window "$target")
    local wname
    wname=$(get_window_name "$wid")

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[dry-run] Would focus: $wname (ID $wid)"
        [[ "$JSON_OUTPUT" == "true" ]] && json_result "ok" "[dry-run] Would focus: $wname (ID $wid)"
        return 0
    fi

    info "Focusing: $wname (ID $wid)" >&2
    do_focus "$wid"

    log_action "focus" "$wname (ID $wid)"
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        json_result "ok" "Focused: $wname (ID $wid)"
    else
        ok "Focused: $wname"
    fi
}

# ---------------------------------------------------------------------------
# click <x> <y> [--window <pattern>] [--button <1|2|3>]
# ---------------------------------------------------------------------------

cmd_click() {
    acquire_desktop_lock
    parse_action_flags "$@"

    # Map button names to numbers
    case "$OPT_BUTTON" in
        left)   OPT_BUTTON=1 ;;
        middle) OPT_BUTTON=2 ;;
        right)  OPT_BUTTON=3 ;;
    esac

    local x="${POSITIONAL[0]:-}"
    local y="${POSITIONAL[1]:-}"

    if [[ -z "$x" || -z "$y" ]]; then
        err "Usage: linux-computer click <x> <y> [--window <pattern>] [--button <1|2|3|left|middle|right>]"
        exit 1
    fi

    require_xdotool

    if [[ "$DRY_RUN" == "true" ]]; then
        local msg="[dry-run] Would click button $OPT_BUTTON at ($x,$y)"
        [[ -n "$OPT_WINDOW" ]] && msg="$msg in window '$OPT_WINDOW'"
        info "$msg"
        [[ "$JSON_OUTPUT" == "true" ]] && json_result "ok" "$msg"
        return 0
    fi

    if [[ -n "$OPT_WINDOW" ]]; then
        local wid
        wid=$(find_window_id "$OPT_WINDOW") || {
            err "No window found matching: $OPT_WINDOW"
            exit 1
        }
        local wname
        wname=$(get_window_name "$wid")
        info "Clicking ($x,$y) in window: $wname (ID $wid)" >&2

        do_focus "$wid"
        DISPLAY="$DISPLAY" xdotool mousemove --window "$wid" "$x" "$y" click "$OPT_BUTTON"
    else
        info "Clicking button $OPT_BUTTON at screen ($x,$y)" >&2
        DISPLAY="$DISPLAY" xdotool mousemove "$x" "$y" click "$OPT_BUTTON"
    fi

    # 50ms settle after click
    sleep 0.05

    log_action "click" "button=$OPT_BUTTON x=$x y=$y window=${OPT_WINDOW:-screen}"
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        json_result "ok" "Clicked at ($x,$y)"
    else
        ok "Clicked at ($x,$y)"
    fi
}

# ---------------------------------------------------------------------------
# type <text> [--window <pattern>]
# ---------------------------------------------------------------------------

cmd_type() {
    acquire_desktop_lock
    parse_action_flags "$@"

    local text="${POSITIONAL[0]:-}"

    if [[ -z "$text" ]]; then
        err "Usage: linux-computer type <text> [--window <pattern>]"
        exit 1
    fi

    require_xdotool

    if [[ "$DRY_RUN" == "true" ]]; then
        local msg="[dry-run] Would type: ${text:0:40}$([ ${#text} -gt 40 ] && printf '...')"
        info "$msg"
        [[ "$JSON_OUTPUT" == "true" ]] && json_result "ok" "$msg"
        return 0
    fi

    if [[ -n "$OPT_WINDOW" ]]; then
        local wid
        wid=$(find_window_id "$OPT_WINDOW") || {
            err "No window found matching: $OPT_WINDOW"
            exit 1
        }
        local wname
        wname=$(get_window_name "$wid")
        info "Typing into window: $wname (ID $wid)" >&2
        do_focus "$wid"
    fi

    DISPLAY="$DISPLAY" xdotool type --clearmodifiers --delay 50 -- "$text"

    log_action "type" "text=${text:0:40}$([ ${#text} -gt 40 ] && printf '...') window=${OPT_WINDOW:-focused}"
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        json_result "ok" "Typed ${#text} characters"
    else
        ok "Typed ${#text} characters"
    fi
}

# ---------------------------------------------------------------------------
# key <key_name> [--window <pattern>]
# ---------------------------------------------------------------------------

cmd_key() {
    acquire_desktop_lock
    parse_action_flags "$@"

    local key="${POSITIONAL[0]:-}"

    if [[ -z "$key" ]]; then
        err "Usage: linux-computer key <key_name> [--window <pattern>]"
        err "Examples: Return, Escape, Tab, space, ctrl+c, alt+F4, shift+Tab"
        exit 1
    fi

    require_xdotool

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[dry-run] Would press key: $key"
        [[ "$JSON_OUTPUT" == "true" ]] && json_result "ok" "[dry-run] Would press key: $key"
        return 0
    fi

    if [[ -n "$OPT_WINDOW" ]]; then
        local wid
        wid=$(find_window_id "$OPT_WINDOW") || {
            err "No window found matching: $OPT_WINDOW"
            exit 1
        }
        local wname
        wname=$(get_window_name "$wid")
        info "Sending key '$key' to window: $wname (ID $wid)" >&2
        do_focus "$wid"
    fi

    DISPLAY="$DISPLAY" xdotool key "$key"

    log_action "key" "key=$key window=${OPT_WINDOW:-focused}"
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        json_result "ok" "Pressed: $key"
    else
        ok "Pressed: $key"
    fi
}

# ---------------------------------------------------------------------------
# move <x> <y> [--window <pattern>]
# ---------------------------------------------------------------------------

cmd_move() {
    acquire_desktop_lock
    parse_action_flags "$@"

    local x="${POSITIONAL[0]:-}"
    local y="${POSITIONAL[1]:-}"

    if [[ -z "$x" || -z "$y" ]]; then
        err "Usage: linux-computer move <x> <y> [--window <pattern>]"
        exit 1
    fi

    require_xdotool

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[dry-run] Would move mouse to ($x,$y)"
        [[ "$JSON_OUTPUT" == "true" ]] && json_result "ok" "[dry-run] Would move mouse to ($x,$y)"
        return 0
    fi

    if [[ -n "$OPT_WINDOW" ]]; then
        local wid
        wid=$(find_window_id "$OPT_WINDOW") || {
            err "No window found matching: $OPT_WINDOW"
            exit 1
        }
        DISPLAY="$DISPLAY" xdotool mousemove --window "$wid" "$x" "$y"
    else
        DISPLAY="$DISPLAY" xdotool mousemove "$x" "$y"
    fi

    log_action "move" "x=$x y=$y window=${OPT_WINDOW:-screen}"
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        json_result "ok" "Moved mouse to ($x,$y)"
    else
        ok "Moved mouse to ($x,$y)"
    fi
}

# ---------------------------------------------------------------------------
# drag <x1> <y1> <x2> <y2> [--window <pattern>]
# ---------------------------------------------------------------------------

cmd_drag() {
    acquire_desktop_lock
    parse_action_flags "$@"

    local x1="${POSITIONAL[0]:-}"
    local y1="${POSITIONAL[1]:-}"
    local x2="${POSITIONAL[2]:-}"
    local y2="${POSITIONAL[3]:-}"

    if [[ -z "$x1" || -z "$y1" || -z "$x2" || -z "$y2" ]]; then
        err "Usage: linux-computer drag <x1> <y1> <x2> <y2> [--window <pattern>]"
        exit 1
    fi

    require_xdotool

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[dry-run] Would drag from ($x1,$y1) to ($x2,$y2)"
        [[ "$JSON_OUTPUT" == "true" ]] && json_result "ok" "[dry-run] Would drag from ($x1,$y1) to ($x2,$y2)"
        return 0
    fi

    if [[ -n "$OPT_WINDOW" ]]; then
        local wid
        wid=$(find_window_id "$OPT_WINDOW") || {
            err "No window found matching: $OPT_WINDOW"
            exit 1
        }
        local wname
        wname=$(get_window_name "$wid")
        info "Dragging in window: $wname (ID $wid)" >&2
        do_focus "$wid"
        DISPLAY="$DISPLAY" xdotool mousemove --window "$wid" "$x1" "$y1" \
            mousedown 1 \
            mousemove --window "$wid" "$x2" "$y2" \
            mouseup 1
    else
        DISPLAY="$DISPLAY" xdotool mousemove "$x1" "$y1" \
            mousedown 1 \
            mousemove "$x2" "$y2" \
            mouseup 1
    fi

    log_action "drag" "from=($x1,$y1) to=($x2,$y2) window=${OPT_WINDOW:-screen}"
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        json_result "ok" "Dragged from ($x1,$y1) to ($x2,$y2)"
    else
        ok "Dragged from ($x1,$y1) to ($x2,$y2)"
    fi
}

# ---------------------------------------------------------------------------
# scroll <x> <y> <direction> [clicks] [--window <pattern>]
# direction: up/down/left/right -> xdotool button 4/5/6/7
# ---------------------------------------------------------------------------

cmd_scroll() {
    acquire_desktop_lock
    parse_action_flags "$@"

    local x="${POSITIONAL[0]:-}"
    local y="${POSITIONAL[1]:-}"
    local direction="${POSITIONAL[2]:-}"
    local clicks="${POSITIONAL[3]:-3}"

    if [[ -z "$x" || -z "$y" || -z "$direction" ]]; then
        err "Usage: linux-computer scroll <x> <y> <direction> [clicks]"
        err "direction: up, down, left, right. Default clicks: 3"
        exit 1
    fi

    local button
    case "$direction" in
        up)    button=4 ;;
        down)  button=5 ;;
        left)  button=6 ;;
        right) button=7 ;;
        *)
            err "scroll: invalid direction '$direction'. Use: up, down, left, right"
            exit 1
            ;;
    esac

    if ! [[ "$clicks" =~ ^[0-9]+$ ]] || [[ "$clicks" -lt 1 ]]; then
        err "scroll: clicks must be a positive integer, got: $clicks"
        exit 1
    fi

    require_xdotool

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[dry-run] Would scroll $direction $clicks clicks at ($x,$y)"
        [[ "$JSON_OUTPUT" == "true" ]] && json_result "ok" "[dry-run] Would scroll $direction $clicks clicks at ($x,$y)"
        return 0
    fi

    if [[ -n "$OPT_WINDOW" ]]; then
        local wid
        wid=$(find_window_id "$OPT_WINDOW") || {
            err "No window found matching: $OPT_WINDOW"
            exit 1
        }
        do_focus "$wid"
        DISPLAY="$DISPLAY" xdotool mousemove --window "$wid" "$x" "$y"
    else
        DISPLAY="$DISPLAY" xdotool mousemove "$x" "$y"
    fi

    # Send scroll clicks
    for (( i=0; i<clicks; i++ )); do
        DISPLAY="$DISPLAY" xdotool click "$button"
    done

    log_action "scroll" "direction=$direction clicks=$clicks x=$x y=$y window=${OPT_WINDOW:-screen}"
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        json_result "ok" "Scrolled $direction $clicks clicks at ($x,$y)"
    else
        ok "Scrolled $direction $clicks clicks at ($x,$y)"
    fi
}

# ---------------------------------------------------------------------------
# wait <ms>
# ---------------------------------------------------------------------------

cmd_wait() {
    local ms="${1:-}"

    if [[ -z "$ms" ]]; then
        err "Usage: linux-computer wait <milliseconds>"
        exit 1
    fi

    if ! [[ "$ms" =~ ^[0-9]+$ ]]; then
        err "wait: milliseconds must be a positive integer, got: $ms"
        exit 1
    fi

    local secs
    secs=$(awk -v ms="$ms" 'BEGIN { printf "%.3f", ms / 1000 }')

    log_action "wait" "${ms}ms"
    sleep "$secs"
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        json_result "ok" "Waited ${ms}ms"
    else
        ok "Waited ${ms}ms"
    fi
}

# ---------------------------------------------------------------------------
# status — generic system status (display, deps, resolution, visible windows)
# ---------------------------------------------------------------------------

cmd_status() {
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        cmd_status_json
        return
    fi

    bold "=== linux-computer status ==="
    printf "\n"

    # Display
    printf "  %-28s %s\n" "DISPLAY:" "$DISPLAY"
    printf "  %-28s %s\n" "XDG_SESSION_TYPE:" "${XDG_SESSION_TYPE:-unset}"

    # Check DISPLAY is accessible
    local display_ok="no"
    if command -v xdotool &>/dev/null; then
        if DISPLAY="$DISPLAY" xdotool getmouselocation &>/dev/null 2>&1; then
            display_ok="yes"
        fi
    fi
    printf "  %-28s %s\n" "Display accessible:" "$display_ok"

    # xdotool
    local xdotool_ver="not found"
    if command -v xdotool &>/dev/null; then
        xdotool_ver=$(xdotool version 2>/dev/null | head -1 || printf "found")
    fi
    printf "  %-28s %s\n" "xdotool:" "$xdotool_ver"

    # scrot
    local scrot_ver="not found"
    if command -v scrot &>/dev/null; then
        scrot_ver=$(scrot --version 2>&1 | head -1 || printf "found")
    fi
    printf "  %-28s %s\n" "scrot:" "$scrot_ver"

    # import (ImageMagick)
    local import_ver="not found"
    if command -v import &>/dev/null; then
        import_ver=$(import --version 2>&1 | head -1 | grep -oP 'ImageMagick [0-9.]+' || printf "found")
    fi
    printf "  %-28s %s\n" "import (ImageMagick):" "$import_ver"

    # Screen resolution
    local resolution="unknown"
    if command -v xdpyinfo &>/dev/null; then
        resolution=$(DISPLAY="$DISPLAY" xdpyinfo 2>/dev/null | grep 'dimensions:' | awk '{print $2}' || true)
    fi
    if [[ -z "$resolution" || "$resolution" == "unknown" ]] && command -v xrandr &>/dev/null; then
        resolution=$(DISPLAY="$DISPLAY" xrandr 2>/dev/null | grep '\*' | head -1 | awk '{print $1}' || true)
    fi
    printf "  %-28s %s\n" "Screen resolution:" "${resolution:-unknown}"

    printf "\n"

    # All visible windows
    bold "Visible windows:"
    printf "\n"

    if command -v xdotool &>/dev/null && [[ "$display_ok" == "yes" ]]; then
        local ids
        ids=$(DISPLAY="$DISPLAY" xdotool search --onlyvisible --name "" 2>/dev/null || true)
        if [[ -n "$ids" ]]; then
            while IFS= read -r wid; do
                [[ -z "$wid" ]] && continue
                local wname geom
                wname=$(get_window_name "$wid")
                # Skip windows with empty names
                [[ -z "$wname" || "$wname" == "(unknown)" ]] && continue
                geom=$(DISPLAY="$DISPLAY" xdotool getwindowgeometry "$wid" 2>/dev/null \
                    | grep -i 'geometry\|position\|size' | tr '\n' ' ' | tr -s ' ' | sed 's/^ //' || true)
                printf "  ID %-12s  %s\n" "$wid" "$wname"
                [[ -n "$geom" ]] && printf "    %s\n" "$geom"
            done <<< "$ids"
        else
            info "No visible windows found."
        fi
    else
        warn "Cannot search windows — xdotool unavailable or display not accessible."
    fi

    printf "\n"

    # Output directory
    printf "  %-28s %s\n" "Output directory:" "$OUTPUT_DIR"
    if [[ -d "$OUTPUT_DIR" ]]; then
        local sc_count
        sc_count=$(find "$OUTPUT_DIR" -maxdepth 1 -name "*.png" -type f 2>/dev/null | wc -l)
        printf "  %-28s %d screenshot(s)\n" "Stored screenshots:" "$sc_count"
    fi

    if [[ -f "$LOG_FILE" ]]; then
        local log_lines
        log_lines=$(wc -l < "$LOG_FILE" 2>/dev/null || printf "0")
        printf "  %-28s %s (%d entries)\n" "Action log:" "$LOG_FILE" "$log_lines"
    fi
}

cmd_status_json() {
    local display_ok="false"
    if command -v xdotool &>/dev/null; then
        if DISPLAY="$DISPLAY" xdotool getmouselocation &>/dev/null 2>&1; then
            display_ok="true"
        fi
    fi

    local resolution="unknown"
    if command -v xdpyinfo &>/dev/null; then
        resolution=$(DISPLAY="$DISPLAY" xdpyinfo 2>/dev/null | grep 'dimensions:' | awk '{print $2}' || true)
    fi
    if [[ -z "$resolution" || "$resolution" == "unknown" ]] && command -v xrandr &>/dev/null; then
        resolution=$(DISPLAY="$DISPLAY" xrandr 2>/dev/null | grep '\*' | head -1 | awk '{print $1}' || true)
    fi

    local has_xdotool="false" has_scrot="false" has_import="false"
    command -v xdotool &>/dev/null && has_xdotool="true"
    command -v scrot &>/dev/null && has_scrot="true"
    command -v import &>/dev/null && has_import="true"

    printf '{"display":"%s","session_type":"%s","display_accessible":%s,"resolution":"%s","xdotool":%s,"scrot":%s,"import":%s}\n' \
        "$(json_str "$DISPLAY")" \
        "$(json_str "${XDG_SESSION_TYPE:-unset}")" \
        "$display_ok" \
        "$(json_str "${resolution:-unknown}")" \
        "$has_xdotool" "$has_scrot" "$has_import"
}

# ---------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------

cmd_usage() {
    cat <<'USAGE'
linux-computer — Linux computer-use tool for AI agents

Usage: linux-computer <command> [options]

Commands:
  screenshot [--window <pattern>] [--output <path>]
      Capture full screen or a specific window.

  find-window <name_pattern>
      List windows matching the given name pattern.

  focus <window_id_or_name> [--dry-run]
      Focus a window by ID or name pattern.

  click <x> <y> [--window <pattern>] [--button <1|2|3>] [--dry-run]
      Click at screen or window-relative coordinates.

  type <text> [--window <pattern>] [--dry-run]
      Type text into the focused or specified window.

  key <key_name> [--window <pattern>] [--dry-run]
      Send a key press. Examples: Return, Escape, ctrl+c, alt+F4

  move <x> <y> [--window <pattern>]
      Move mouse cursor to coordinates.

  drag <x1> <y1> <x2> <y2> [--window <pattern>]
      Drag from one point to another.

  scroll <x> <y> <direction> [clicks] [--window <pattern>]
      Scroll at coordinates. Direction: up/down/left/right. Default: 3 clicks.

  wait <milliseconds>
      Sleep for the specified duration.

  status
      Show display info, dependencies, resolution, and visible windows.

  lock-status
      Show desktop exclusivity lock state.

Global flags:
  --json        Output results as JSON objects (for programmatic use).
  --help, -h    Show this help message.

Dependencies: xdotool, scrot, imagemagick (import)
USAGE
}

# ---------------------------------------------------------------------------
# Global flag parsing: extract --json before dispatching
# ---------------------------------------------------------------------------

args=()
for arg in "$@"; do
    case "$arg" in
        --json)
            JSON_OUTPUT="true"
            # Re-blank colors when switching to JSON mode
            RED="" GREEN="" YELLOW="" CYAN="" BOLD="" DIM="" RESET=""
            ;;
        *)
            args+=("$arg")
            ;;
    esac
done
set -- "${args[@]+"${args[@]}"}"

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

case "${1:-}" in
    screenshot)      shift; cmd_screenshot "$@" ;;
    find-window)     shift; cmd_find_window "$@" ;;
    focus)           shift; cmd_focus "$@" ;;
    click)           shift; cmd_click "$@" ;;
    type)            shift; cmd_type "$@" ;;
    key)             shift; cmd_key "$@" ;;
    move)            shift; cmd_move "$@" ;;
    drag)            shift; cmd_drag "$@" ;;
    scroll)          shift; cmd_scroll "$@" ;;
    wait)            shift; cmd_wait "$@" ;;
    status)          shift; cmd_status ;;
    lock-status)     cmd_lock_status ;;
    --help|-h|help|"") cmd_usage ;;
    *)               err "Unknown command: $1"; cmd_usage; exit 1 ;;
esac
