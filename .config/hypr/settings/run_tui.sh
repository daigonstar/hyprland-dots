#!/bin/sh
# Launcher script to run the Hypr settings TUI in a terminal.
#
# Installs no dependencies and tries to be robust:
# - If called from an existing terminal, use --inside to run in-place.
# - Otherwise it will try to find a terminal emulator and spawn the TUI there,
#   detaching so this script returns immediately (suitable for Waybar `on-click`).
#
# Usage:
#   run_tui.sh [keybinds|autostart]      # spawn a terminal and run the TUI (default: keybinds)
#   run_tui.sh --inside [keybinds]      # run the TUI in the current terminal process
#   run_tui.sh --help
#
# Notes:
# - The script looks for the TUI at $XDG_CONFIG_HOME/hypr/settings/tui.py or
#   $HOME/.config/hypr/settings/tui.py if XDG_CONFIG_HOME is not set.
# - It will attempt to use $TERMINAL (if set) or a list of common terminals.
# - If no terminal is found and --inside is not used, the script prints an error.

set -eu

# Resolve paths
XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
TUI="$XDG_CONFIG_HOME/hypr/settings/tui.py"
PYTHON=${PYTHON:-python3}

usage() {
    cat <<EOF
Usage: $(basename "$0") [--inside] [keybinds|autostart]

Options:
  --inside     Run the TUI in the current terminal (do not spawn a new emulator).
  keybinds     Edit ~/.config/hypr/keybinds.conf (default)
  autostart    Edit ~/.config/hypr/autostart.conf
  --help       Show this message
EOF
}

# Check TUI exists
if [ ! -f "$TUI" ]; then
    echo "Error: TUI script not found at: $TUI" >&2
    echo "Ensure the TUI is installed to that path before running this launcher." >&2
    exit 2
fi

# Parse args
MODE="spawn"
TARGET="keybinds"
if [ $# -gt 0 ]; then
    case "$1" in
        --help|-h)
            usage
            exit 0
            ;;
        --inside)
            MODE="inside"
            shift
            ;;
    esac
fi

if [ $# -gt 0 ]; then
    case "$1" in
        keybinds|autostart)
            TARGET="$1"
            ;;
        *)
            echo "Unknown target: $1" >&2
            usage
            exit 2
            ;;
    esac
fi

# If requested to run inside current terminal, just exec the python script
if [ "$MODE" = "inside" ]; then
    exec "$PYTHON" "$TUI" "$TARGET"
fi

# Otherwise try to find a terminal emulator
# Respect $TERMINAL env if set and points to an executable
if [ -n "${TERMINAL:-}" ] && command -v "$TERMINAL" >/dev/null 2>&1; then
    TERM_CMD=$(command -v "$TERMINAL")
else
    # Common terminals; order chosen for common Wayland-friendly emulators
    for t in foot alacritty kitty wezterm gnome-terminal xfce4-terminal konsole st xterm rxvt urxvt lxterminal; do
        if command -v "$t" >/dev/null 2>&1; then
            TERM_CMD=$(command -v "$t")
            break
        fi
    done
fi

if [ -z "${TERM_CMD:-}" ]; then
    echo "No terminal emulator found. Either set the TERMINAL env var or install a terminal (e.g. foot, alacritty, kitty, gnome-terminal, xterm)." >&2
    exit 3
fi

# Construct a safe detached command to run the TUI inside a terminal.
# We try to handle a few known terminals explicitly because flags vary.
run_in_terminal() {
    term=$(basename "$TERM_CMD")
    case "$term" in
        foot|alacritty|kitty|st|xterm|rxvt|urxvt|lxterminal|konsole)
            # these typically support: <term> -e <command...>
            # Use setsid to detach so the launcher can return immediately.
            setsid "$TERM_CMD" -e "$PYTHON" "$TUI" "$TARGET" >/dev/null 2>&1 &
            ;;
        gnome-terminal)
            # gnome-terminal prefers: gnome-terminal -- <command...>
            # Use bash -lc so the terminal stays open briefly if the program exits unexpectedly.
            setsid "$TERM_CMD" -- bash -lc "\"$PYTHON\" \"$TUI\" \"$TARGET\"; exec bash" >/dev/null 2>&1 &
            ;;
        wezterm)
            # wezterm's CLI can spawn a command; try `wezterm` with `cli spawn` if available,
            # but using -e might still work on many installs. Try simple invocation first.
            if "$TERM_CMD" --help 2>&1 | grep -q "cli"; then
                # attempt to use wezterm cli spawn (best-effort)
                setsid "$TERM_CMD" cli spawn --command "$PYTHON" "$TUI" "$TARGET" >/dev/null 2>&1 || \
                    setsid "$TERM_CMD" -e "$PYTHON" "$TUI" "$TARGET" >/dev/null 2>&1 &
            else
                setsid "$TERM_CMD" -e "$PYTHON" "$TUI" "$TARGET" >/dev/null 2>&1 &
            fi
            ;;
        *)
            # Fallback: try -e
            setsid "$TERM_CMD" -e "$PYTHON" "$TUI" "$TARGET" >/dev/null 2>&1 &
            ;;
    esac

    # Return success even if the exact terminal flags were non-ideal; the process was detached.
    return 0
}

run_in_terminal

# Give a brief, machine-readable success exit
exit 0
