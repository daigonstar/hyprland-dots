#!/usr/bin/env python3
"""
Hyprland Settings TUI

- Edits two files (plain-line, preserves comments/blank lines):
    ~/.config/hypr/keybinds.conf
    ~/.config/hypr/autostart.conf

- Visual representation of Hyprland bind lines grouped by category comments.
- Selection-driven column editor with preview pane and Modifiers chooser.
- Atomic saves with timestamped backups.

Usage:
  python3 ~/.config/hypr/settings/tui.py [keybinds|autostart]

Notes:
- Parser is conservative: detects lines starting with "bind*" and splits by commas.
- Comments that start with "# Category:" are treated as section headings.
- The main listing no longer prints line numbers; it renders category headings
  and the file lines in order. Bind conflicts (same modifiers + key) are
  highlighted in red when the terminal supports colors.
"""

from __future__ import annotations

import curses
import os
import re
import shutil
import tempfile
import time
from typing import Dict, List, Optional, Tuple

HOME = os.path.expanduser("~")
CONFIG_DIR = os.path.join(HOME, ".config", "hypr")
FILES = {
    "keybinds": os.path.join(CONFIG_DIR, "keybinds.conf"),
    "autostart": os.path.join(CONFIG_DIR, "autostart.conf"),
}


# ---------- Utilities ----------


def ensure_paths() -> None:
    os.makedirs(CONFIG_DIR, exist_ok=True)
    for p in FILES.values():
        if not os.path.exists(p):
            with open(p, "w", encoding="utf-8") as f:
                f.write("# created by hypr settings tui\n")


def timestamp() -> str:
    return time.strftime("%Y%m%d-%H%M%S")


def backup_file(path: str) -> str:
    ts = timestamp()
    base = os.path.basename(path)
    dirn = os.path.dirname(path)
    dst = os.path.join(dirn, f"{base}.bak.{ts}")
    shutil.copy2(path, dst)
    return dst


def atomic_write(path: str, content_lines: List[str]) -> None:
    dirn = os.path.dirname(path)
    fd, tmp = tempfile.mkstemp(prefix=".tmp-hypr-", dir=dirn, text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            for line in content_lines:
                if not line.endswith("\n"):
                    f.write(line + "\n")
                else:
                    f.write(line)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)


# ---------- Bind parser (conservative) ----------

BIND_RE = re.compile(r"^\s*(bind\w*)\s*=\s*(.*)$")


def split_n_commas(s: str, n: int) -> List[str]:
    parts: List[str] = []
    remaining = s
    for _ in range(n):
        if "," in remaining:
            left, _, remaining = remaining.partition(",")
            parts.append(left.strip())
        else:
            parts.append(remaining.strip())
            remaining = ""
            break
    if remaining != "":
        parts.append(remaining.strip())
    return parts


def parse_bind_line(line: str) -> Dict:
    """
    Returns a dict:
    {
      'is_bind': bool,
      'raw': original_line,
      'type': 'bind'|'bindm'...,
      'modifiers': '...'
      'key': 'A'|'left'|...
      'action': 'exec'|'move'...
      'args': rest after action (may be empty)
    }
    """
    m = BIND_RE.match(line)
    if not m:
        return {"is_bind": False, "raw": line}
    bind_type = m.group(1)
    rest = m.group(2)
    parts = split_n_commas(rest, 3)
    modifiers = parts[0] if len(parts) > 0 else ""
    key = parts[1] if len(parts) > 1 else ""
    action = parts[2] if len(parts) > 2 else ""
    remainder = parts[3] if len(parts) > 3 else ""
    return {
        "is_bind": True,
        "raw": line,
        "type": bind_type,
        "modifiers": modifiers.strip(),
        "key": key.strip(),
        "action": action.strip(),
        "args": remainder.strip(),
    }


# ---------- Desktop .desktop scanner (unhidden) ----------


def _parse_desktop_file(path: str) -> Tuple[Optional[str], Optional[str], bool]:
    """
    Parse a .desktop file; return (Name, Exec, visible).
    visible is False if NoDisplay or Hidden is true or Type != Application.
    Returns (None, None, False) on error or non-app entries.
    """
    name = None
    exec_cmd = None
    type_app = None
    nodisplay = False
    hidden = False
    try:
        with open(path, "r", encoding="utf-8") as f:
            in_entry = False
            for ln in f:
                ln = ln.strip()
                if not ln:
                    continue
                if ln.startswith("["):
                    in_entry = ln.lower().startswith("[desktop entry]")
                    continue
                if not in_entry:
                    continue
                if ln.startswith("Name=") and name is None:
                    name = ln.split("=", 1)[1]
                elif ln.startswith("Exec="):
                    exec_cmd = ln.split("=", 1)[1]
                elif ln.startswith("Type="):
                    type_app = ln.split("=", 1)[1]
                elif ln.startswith("NoDisplay="):
                    nodisplay = ln.split("=", 1)[1].lower() in ("true", "1")
                elif ln.startswith("Hidden="):
                    hidden = ln.split("=", 1)[1].lower() in ("true", "1")
    except Exception:
        return (None, None, False)
    if type_app and type_app.lower() != "application":
        return (None, None, False)
    if nodisplay or hidden:
        return (None, None, False)
    if name and exec_cmd:
        # remove field codes like %U %u %F %f %i %c
        exec_clean = re.sub(r"\s*%[a-zA-Z@%]", "", exec_cmd).strip()
        return (name, exec_clean, True)
    return (None, None, False)


def scan_desktop_apps() -> List[Tuple[str, str]]:
    """
    Return list of (label, exec) for unhidden desktop entries.
    Label format: 'Name — execcmd'
    """
    paths = [
        os.path.join(HOME, ".local", "share", "applications"),
        "/usr/share/applications",
    ]
    apps: List[Tuple[str, str]] = []
    seen = set()
    for p in paths:
        if not os.path.isdir(p):
            continue
        try:
            for fn in sorted(os.listdir(p)):
                if not fn.endswith(".desktop"):
                    continue
                full = os.path.join(p, fn)
                name, exec_clean, ok = _parse_desktop_file(full)
                if not ok or not name or not exec_clean:
                    continue
                if exec_clean in seen:
                    continue
                seen.add(exec_clean)
                label = f"{name} — {exec_clean}"
                apps.append((label, exec_clean))
        except Exception:
            continue
    return apps


# ---------- Line-list model ----------


class LineList:
    def __init__(self, path: str):
        self.path = path
        self.load()
        self.dirty = False

    def load(self):
        with open(self.path, "r", encoding="utf-8") as f:
            self.lines: List[str] = [ln.rstrip("\n") for ln in f.readlines()]

    def reload(self):
        self.load()
        self.dirty = False

    def toggle(self, idx: int) -> None:
        line = self.lines[idx]
        if line.strip().startswith("#"):
            prefix_ws = line[: len(line) - len(line.lstrip())]
            uncommented = line[len(prefix_ws) :].lstrip("#")
            if uncommented.startswith(" "):
                uncommented = uncommented[1:]
            self.lines[idx] = prefix_ws + uncommented
        else:
            prefix_ws = line[: len(line) - len(line.lstrip())]
            self.lines[idx] = prefix_ws + "# " + line[len(prefix_ws) :]
        self.dirty = True

    def insert_after(self, idx: int, text: str) -> None:
        self.lines.insert(idx + 1, text)
        self.dirty = True

    def append(self, text: str) -> None:
        self.lines.append(text)
        self.dirty = True

    def edit(self, idx: int, text: str) -> None:
        self.lines[idx] = text
        self.dirty = True

    def delete(self, idx: int) -> None:
        del self.lines[idx]
        self.dirty = True

    def move_up(self, idx: int) -> int:
        if idx <= 0:
            return idx
        self.lines[idx - 1], self.lines[idx] = self.lines[idx], self.lines[idx - 1]
        self.dirty = True
        return idx - 1

    def move_down(self, idx: int) -> int:
        if idx >= len(self.lines) - 1:
            return idx
        self.lines[idx + 1], self.lines[idx] = self.lines[idx], self.lines[idx + 1]
        self.dirty = True
        return idx + 1

    def save(self) -> None:
        backup_file(self.path)
        atomic_write(self.path, self.lines)
        self.dirty = False


# ---------- UI helpers ----------


def choose_from_list(
    stdscr, title: str, items: List[str], selected_idx: int = 0
) -> Tuple[int, str]:
    """Simple selectable list modal. Return (index, value) or (-1, "") on cancel."""
    h, w = stdscr.getmaxyx()
    win_h = min(len(items) + 4, h - 4)
    win_w = min(max(40, max((len(i) for i in items), default=40) + 4), w - 4)
    win = curses.newwin(
        win_h, win_w, max(1, (h - win_h) // 2), max(1, (w - win_w) // 2)
    )
    win.keypad(True)
    cur = max(0, min(selected_idx, len(items) - 1))
    while True:
        win.erase()
        win.border()
        try:
            win.addnstr(0, 2, f" {title} ", win_w - 4, curses.A_REVERSE)
        except curses.error:
            pass
        max_items = win_h - 4
        start = 0 if cur < max_items else cur - max_items + 1
        for i in range(start, min(start + max_items, len(items))):
            label = items[i]
            marker = ">" if i == cur else " "
            try:
                win.addnstr(
                    1 + i - start, 2, f"{marker} {label}", win_w - 4, curses.A_NORMAL
                )
            except curses.error:
                pass
        win.refresh()
        ch = win.getch()
        if ch == curses.KEY_MOUSE:
            try:
                _, x, y, _, bstate = curses.getmouse()
                # Get window's top-left corner coordinates on the screen
                win_y, win_x = win.getbegyx()
                # Calculate y-coordinate relative to the window content area
                relative_y = y - win_y - 1  # -1 because content starts at y=1

                # Check if click is within the displayed items and is a left click
                if bstate & curses.BUTTON1_PRESSED and 0 <= relative_y < max_items:
                    clicked_item_idx_relative = relative_y
                    clicked_item_file_idx = start + clicked_item_idx_relative
                    if 0 <= clicked_item_file_idx < len(items):
                        return clicked_item_file_idx, items[clicked_item_file_idx]
            except curses.error:
                pass  # Mouse event outside window, ignore
        elif ch in (curses.KEY_UP, ord("k")):
            if cur > 0:
                cur -= 1
        elif ch in (curses.KEY_DOWN, ord("j")):
            if cur < len(items) - 1:
                cur += 1
        elif ch in (ord("\n"), ord("\r"), ord(" ")):
            return cur, items[cur]
        elif ch in (27,):  # ESC
            return -1, ""
        elif ch == curses.KEY_NPAGE:
            cur = min(len(items) - 1, cur + max_items)
        elif ch == curses.KEY_PPAGE:
            cur = max(0, cur - max_items)


def small_input(stdscr, prompt_text: str, initial: str = "") -> str:
    """Small single-line input prompt; returns text or empty string."""
    h, w = stdscr.getmaxyx()
    win_h = 3
    win_w = min(w - 4, max(40, len(prompt_text) + len(initial) + 10))
    win = curses.newwin(win_h, win_w, max(1, h - win_h - 2), 2)
    win.border()
    try:
        win.addnstr(1, 1, f"{prompt_text}: {initial}", win_w - 4)
        win.refresh()
    except curses.error:
        pass
    curses.echo()
    stdscr.move(h - win_h - 1, len(prompt_text) + 3 + len(initial))
    try:
        inp = stdscr.getstr(h - win_h - 1, len(prompt_text) + 3 + len(initial), 8192)
    except Exception:
        inp = None
    curses.noecho()
    return inp.decode("utf-8") if inp else ""


# ---------- Curses TUI ----------


class Tui:
    def __init__(self, stdscr, model_name: str):
        self.stdscr = stdscr
        curses.curs_set(0)
        curses.mousemask(curses.ALL_MOUSE_EVENTS | curses.REPORT_MOUSE_POSITION)
        # initialize colors if available (used to highlight duplicates)
        self.has_colors = False
        if curses.has_colors():
            try:
                curses.start_color()
                curses.use_default_colors()
                curses.init_pair(
                    1, curses.COLOR_RED, -1
                )  # red foreground for conflicts
                self.has_colors = True
            except Exception:
                # color init failure shouldn't stop the TUI
                self.has_colors = False

        self.model_name = model_name
        self.model = LineList(FILES[model_name])
        self.cursor = 0  # index into model.lines (file line index)
        self.top = 0
        self.status = f"Loaded {os.path.basename(self.model.path)}"
        self.height, self.width = self.stdscr.getmaxyx()
        # cached desktop apps (scanned at startup)
        self.apps = scan_desktop_apps()
        # runtime caches
        self._conflicts = set()  # set of (modifiers, key) tuples indicating conflicts

    def draw(self):
        """
        Render the file without line numbers, using '# Category: name' comments
        as section headings. The visual ordering matches file order. The cursor
        still refers to the file line index; the current line is marked with '>'.
        """
        self.stdscr.erase()
        self.height, self.width = self.stdscr.getmaxyx()
        self._screen_to_file_map: Dict[int, int] = {}  # Initialize/clear the map
        title = (
            f"hypr settings - {self.model_name} - {os.path.basename(self.model.path)}"
        )
        if self.model.dirty:
            title += " [modified]"
        try:
            self.stdscr.addnstr(0, 0, title, self.width, curses.A_REVERSE)
        except curses.error:
            pass

        visible_h = self.height - 4
        if visible_h < 3:
            try:
                self.stdscr.addstr(1, 0, "window too small", curses.A_BOLD)
                self.stdscr.refresh()
            except curses.error:
                pass
            return

        # ensure top is within range of cursor
        if self.cursor < self.top:
            self.top = self.cursor
        elif self.cursor >= self.top + visible_h:
            self.top = self.cursor - visible_h + 1

        # Build conflict set based on modifiers+key
        key_list = []
        for ln in self.model.lines:
            p = parse_bind_line(ln)
            if p.get("is_bind"):
                mods = (p.get("modifiers", "") or "").strip()
                key = (p.get("key", "") or "").strip()
                kt = (mods, key)
            else:
                kt = None
            key_list.append(kt)
        self._conflicts = set(
            [kt for kt in key_list if kt and kt[1] != "" and key_list.count(kt) > 1]
        )

        # Column widths for neat bind display (no line numbers)
        col_type_w = 8
        col_mod_w = 20
        col_key_w = 12
        col_action_w = max(12, self.width - (col_type_w + col_mod_w + col_key_w + 10))

        # Render each line in order, but treat '# Category:' specially
        # Track rendered line index -> file line index mapping in case it's useful
        rendered = 0
        start_idx = self.top
        end_idx = min(len(self.model.lines), self.top + visible_h)
        for idx in range(start_idx, end_idx):
            line = self.model.lines[idx]
            y = 1 + (idx - self.top)
            # Store the mapping from screen Y coordinate to file line index
            self._screen_to_file_map[y] = idx
            marker = ">" if idx == self.cursor else " "
            stripped = line.strip()

            # Category heading detection
            if stripped.lower().startswith("# category:"):
                # Extract category name and render as a heading line
                cat = (
                    stripped.split(":", 1)[1].strip()
                    if ":" in stripped
                    else stripped[1:].strip()
                )
                display = f"  {cat}"
                try:
                    # Underline + bold for headings
                    self.stdscr.addnstr(
                        y, 0, display, self.width, curses.A_UNDERLINE | curses.A_BOLD
                    )
                except curses.error:
                    pass
                rendered += 1
                continue

            # Parse binds and choose rendering style
            parsed = parse_bind_line(line)
            try:
                if parsed.get("is_bind"):
                    t = parsed.get("type", "")[:col_type_w].ljust(col_type_w)
                    m = parsed.get("modifiers", "")[:col_mod_w].ljust(col_mod_w)
                    k = parsed.get("key", "")[:col_key_w].ljust(col_key_w)
                    a_full = (
                        parsed.get("action", "") + " " + parsed.get("args", "")
                    ).strip()
                    a = a_full[:col_action_w]
                    display = f"{marker} {t} {m} {k} => {a}"
                    # highlight conflicts (same modifiers + key) in red (if colors available)
                    key_tuple = (
                        (parsed.get("modifiers", "") or "").strip(),
                        (parsed.get("key", "") or "").strip(),
                    )
                    if key_tuple and key_tuple in self._conflicts and self.has_colors:
                        attr = curses.color_pair(1) | curses.A_BOLD
                    else:
                        attr = curses.A_BOLD
                else:
                    # regular comment/other line: show raw with dim attribute
                    display = f"{marker} {line}"
                    attr = (
                        curses.A_DIM
                        if line.strip().startswith("#")
                        else curses.A_NORMAL
                    )

                self.stdscr.addnstr(y, 0, display, self.width, attr)
            except curses.error:
                pass
            rendered += 1

        # Footer/status
        try:
            self.stdscr.hline(self.height - 3, 0, "-", self.width)
            self.stdscr.addnstr(self.height - 2, 0, self.status, self.width)
            self.stdscr.refresh()
        except curses.error:
            pass

    # Reuse select_from_list as instance method for convenience
    def select_from_list(
        self, title: str, options: List[str], allow_custom: bool = False
    ) -> Optional[str]:
        """Display options and return selected string or None."""
        if allow_custom:
            options = list(options) + ["<Custom...>"]
        h, w = self.stdscr.getmaxyx()
        win_h = min(len(options) + 4, h - 6)
        win_w = min(
            max(len(title) + 6, max((len(o) for o in options), default=0) + 6), w - 6
        )
        win = curses.newwin(
            win_h, win_w, max(1, (h - win_h) // 2), max(2, (w - win_w) // 2)
        )
        win.keypad(True)
        win.border()
        try:
            win.addnstr(0, 2, f" {title} ", win_w - 4, curses.A_REVERSE)
        except curses.error:
            pass
        idx = 0
        while True:
            win.erase()
            win.border()
            try:
                win.addnstr(0, 2, f" {title} ", win_w - 4, curses.A_REVERSE)
            except curses.error:
                pass
            max_items = win_h - 4
            start = 0 if idx < max_items else idx - max_items + 1
            for i in range(start, min(start + max_items, len(options))):
                opt = options[i]
                attr = curses.A_REVERSE if i == idx else curses.A_NORMAL
                try:
                    win.addnstr(1 + i - start, 2, opt.ljust(win_w - 4), win_w - 4, attr)
                except curses.error:
                    pass
            win.refresh()
            ch = win.getch()
            if ch in (curses.KEY_UP, ord("k")):
                idx = (idx - 1) % len(options)
            elif ch in (curses.KEY_DOWN, ord("j")):
                idx = (idx + 1) % len(options)
            elif ch in (ord("\n"), ord("\r"), ord(" ")):
                choice = options[idx]
                del win
                if allow_custom and choice == "<Custom...>":
                    return self.prompt("Enter custom value", "")
                return choice
            elif ch in (27,):
                del win
                return None

    def prompt(self, prompt_text: str, initial_text: str = "") -> str:
        """Single-line prompt returning user input."""
        h, w = self.stdscr.getmaxyx()
        win_h = 3
        win_w = min(w - 6, max(40, len(prompt_text) + len(initial_text) + 10))
        win = curses.newwin(win_h, win_w, max(1, h - win_h - 3), 3)
        win.border()
        try:
            win.addnstr(1, 1, f"{prompt_text}: {initial_text}", win_w - 2)
            win.refresh()
        except curses.error:
            pass
        curses.echo()
        self.stdscr.move(h - win_h - 2, len(prompt_text) + 4 + len(initial_text))
        try:
            inp = self.stdscr.getstr(
                h - win_h - 2, len(prompt_text) + 4 + len(initial_text), 8192
            )
        except Exception:
            inp = None
        curses.noecho()
        return inp.decode("utf-8") if inp else ""

    def structured_edit_bind_column(self):
        """
        Column-based editor: columns are [Bind Type | Modifiers | Key | Application]
        Includes a preview pane showing the exact line that will be written.
        """
        if len(self.model.lines) == 0:
            self.status = "Nothing to edit"
            return

        cur_line = self.model.lines[self.cursor]
        parsed = parse_bind_line(cur_line)

        # If not a bind line, fallback to convert or raw edit
        if not parsed.get("is_bind"):
            choice = self.select_from_list(
                "Not a bind: action",
                ["View raw", "Edit raw", "Convert to bind"],
                allow_custom=False,
            )
            if choice is None:
                self.status = "Canceled"
                return
            if choice == "View raw":
                self.status = cur_line
                return
            if choice == "Edit raw":
                new = self.prompt("Edit raw line", cur_line)
                if new:
                    self.model.edit(self.cursor, new)
                    self.status = f"Edited line {self.cursor + 1}"
                return
            if choice == "Convert to bind":
                new_line = "bind = $mainMod, T, exec, $terminal"
                self.model.edit(self.cursor, new_line)
                self.status = "Converted to bind"
                return

        # Available options
        bind_types = ["bind", "bindm", "binde", "bindel", "bindl"]
        modifier_opts = [
            "",
            "$mainMod",
            "$mainMod SHIFT",
            "$mainMod CTRL",
            "$mainMod ALT",
            "SHIFT",
            "CONTROL",
            "ALT",
            "ALT CTRL",
            "ALT SHIFT",
        ]
        key_opts = [chr(c) for c in range(ord("A"), ord("Z") + 1)] + [
            str(n) for n in range(0, 10)
        ]
        key_opts += ["left", "right", "up", "down", "SPACE"] + [
            f"F{i}" for i in range(1, 13)
        ]
        key_opts += ["mouse:272", "mouse:273"]

        # apps list
        apps = self.apps
        app_labels = [a[0] for a in apps]
        # ensure at least one entry
        if not app_labels:
            app_labels = ["<No desktop apps found>"]
            apps = []
        # allow custom marker
        app_labels.append("<Custom...>")

        # Starting values from parsed line
        cur_bind = parsed.get("type", "bind")
        cur_mods = parsed.get("modifiers", "") or "$mainMod"
        cur_key = parsed.get("key", "") or "T"
        cur_app = parsed.get("args", "")

        # find indices for each column, add if missing
        try:
            idx_bind = bind_types.index(cur_bind)
        except ValueError:
            bind_types.append(cur_bind)
            idx_bind = len(bind_types) - 1
        try:
            idx_mod = modifier_opts.index(cur_mods)
        except ValueError:
            modifier_opts.append(cur_mods)
            idx_mod = len(modifier_opts) - 1
        try:
            idx_key = key_opts.index(cur_key)
        except ValueError:
            key_opts.append(cur_key)
            idx_key = len(key_opts) - 1
        # app index: match exec value to apps
        idx_app = -1
        for i, (lbl, execv) in enumerate(apps):
            if execv == cur_app:
                idx_app = i
                break
        if idx_app == -1:
            if cur_app:
                # add as custom label at front for visibility
                app_labels.insert(0, f"Custom: {cur_app}")
                apps.insert(0, (f"Custom: {cur_app}", cur_app))
                idx_app = 0
            else:
                idx_app = 0

        # Editor state
        col = 0  # 0=bind,1=mods,2=key,3=app
        num_cols = 4

        h, w = self.stdscr.getmaxyx()
        win_h = min(14, h - 6)
        win_w = min(w - 6, 100)
        win_y = max(2, (h - win_h) // 2)
        win_x = max(3, (w - win_w) // 2)
        win = curses.newwin(win_h, win_w, win_y, win_x)
        win.keypad(True)

        def build_preview(btype, mods, key, app_exec) -> str:
            parts = []
            if mods:
                parts.append(mods)
            if key:
                parts.append(key)
            # action is exec since we're selecting applications
            if app_exec:
                parts.append("exec")
                parts.append(app_exec)
            # join RHS and prefix bind type
            rhs = ", ".join(parts)
            return f"{btype} = {rhs}"

        while True:
            win.erase()
            win.border()
            try:
                win.addnstr(
                    0,
                    2,
                    " Column editor (Left/Right to switch) ",
                    win_w - 4,
                    curses.A_REVERSE,
                )
            except curses.error:
                pass

            col_w = max(10, (win_w - 6) // num_cols)

            # Column headers
            try:
                win.addnstr(1, 2, "Bind", col_w - 2, curses.A_BOLD)
                win.addnstr(1, 2 + col_w, "Modifiers", col_w - 2, curses.A_BOLD)
                win.addnstr(1, 2 + 2 * col_w, "Key", col_w - 2, curses.A_BOLD)
                win.addnstr(1, 2 + 3 * col_w, "Application", col_w - 2, curses.A_BOLD)
            except curses.error:
                pass

            # Highlight and show selected values
            attr_bind = curses.A_STANDOUT if col == 0 else curses.A_NORMAL
            attr_mods = curses.A_STANDOUT if col == 1 else curses.A_NORMAL
            attr_key = curses.A_STANDOUT if col == 2 else curses.A_NORMAL
            attr_app = curses.A_STANDOUT if col == 3 else curses.A_NORMAL
            try:
                win.addnstr(
                    3, 2, bind_types[idx_bind][: col_w - 2], col_w - 2, attr_bind
                )
                win.addnstr(
                    3,
                    2 + col_w,
                    modifier_opts[idx_mod][: col_w - 2],
                    col_w - 2,
                    attr_mods,
                )
                win.addnstr(
                    3,
                    2 + 2 * col_w,
                    key_opts[idx_key][: col_w - 2],
                    col_w - 2,
                    attr_key,
                )
                label_app = (
                    app_labels[idx_app] if 0 <= idx_app < len(app_labels) else ""
                )
                win.addnstr(
                    3, 2 + 3 * col_w, label_app[: col_w - 2], col_w - 2, attr_app
                )
            except curses.error:
                pass

            # Preview pane below
            preview = build_preview(
                bind_types[idx_bind],
                modifier_opts[idx_mod],
                key_opts[idx_key],
                (apps[idx_app][1] if 0 <= idx_app < len(apps) else cur_app),
            )
            try:
                win.hline(5, 1, "-", win_w - 2)
                win.addnstr(6, 2, "Preview:", win_w - 4, curses.A_DIM)
                win.addnstr(7, 2, preview[: win_w - 4], win_w - 4, curses.A_BOLD)
                win.addnstr(
                    win_h - 3,
                    2,
                    "Enter: chooser  c: custom  s: save  Esc: cancel",
                    win_w - 4,
                    curses.A_DIM,
                )
            except curses.error:
                pass

            win.refresh()
            ch = win.getch()
            if ch in (curses.KEY_LEFT, ord("h")):
                col = (col - 1) % num_cols
            elif ch in (curses.KEY_RIGHT, ord("l")):
                col = (col + 1) % num_cols
            elif ch in (curses.KEY_UP, ord("k")):
                if col == 0:
                    idx_bind = (idx_bind - 1) % len(bind_types)
                elif col == 1:
                    idx_mod = (idx_mod - 1) % len(modifier_opts)
                elif col == 2:
                    idx_key = (idx_key - 1) % len(key_opts)
                else:
                    idx_app = (idx_app - 1) % len(app_labels)
            elif ch in (curses.KEY_DOWN, ord("j")):
                if col == 0:
                    idx_bind = (idx_bind + 1) % len(bind_types)
                elif col == 1:
                    idx_mod = (idx_mod + 1) % len(modifier_opts)
                elif col == 2:
                    idx_key = (idx_key + 1) % len(key_opts)
                else:
                    idx_app = (idx_app + 1) % len(app_labels)
            elif ch in (ord("\n"), ord("\r")):
                # detailed chooser for focused column
                if col == 0:
                    sel = self.select_from_list(
                        "Bind type", bind_types, allow_custom=True
                    )
                    if sel:
                        if sel not in bind_types:
                            bind_types.append(sel)
                        idx_bind = bind_types.index(sel)
                elif col == 1:
                    sel = self.select_from_list(
                        "Modifiers", modifier_opts, allow_custom=True
                    )
                    if sel is not None:
                        if sel not in modifier_opts:
                            modifier_opts.append(sel)
                        idx_mod = modifier_opts.index(sel)
                elif col == 2:
                    sel = self.select_from_list("Key", key_opts, allow_custom=True)
                    if sel:
                        if sel not in key_opts:
                            key_opts.append(sel)
                        idx_key = key_opts.index(sel)
                else:
                    sel = self.select_from_list(
                        "Application", app_labels, allow_custom=True
                    )
                    if sel is None:
                        pass
                    elif sel == "<Custom...>":
                        custom = self.prompt("Enter custom application exec", cur_app)
                        if custom:
                            cur_app = custom
                            app_labels.insert(0, f"Custom: {custom}")
                            apps.insert(0, (f"Custom: {custom}", custom))
                            idx_app = 0
                    else:
                        # sel matches label; find in apps
                        for i, (lbl, ex) in enumerate(apps):
                            if lbl == sel:
                                idx_app = i
                                break
            elif ch in (ord("c"), ord("C")):
                # quick custom input for focused column
                if col == 0:
                    custom = self.prompt("Custom bind type", bind_types[idx_bind])
                    if custom:
                        if custom not in bind_types:
                            bind_types.append(custom)
                        idx_bind = bind_types.index(custom)
                elif col == 1:
                    custom = self.prompt("Custom modifiers", modifier_opts[idx_mod])
                    if custom:
                        if custom not in modifier_opts:
                            modifier_opts.append(custom)
                        idx_mod = modifier_opts.index(custom)
                elif col == 2:
                    custom = self.prompt("Custom key", key_opts[idx_key])
                    if custom:
                        if custom not in key_opts:
                            key_opts.append(custom)
                        idx_key = key_opts.index(custom)
                else:
                    custom = self.prompt("Custom application exec", cur_app)
                    if custom:
                        cur_app = custom
                        app_labels.insert(0, f"Custom: {custom}")
                        apps.insert(0, (f"Custom: {custom}", custom))
                        idx_app = 0
            elif ch in (ord("s"), ord("S")):
                # Save: write assembled line into model (bind type + modifiers + key + exec)
                sel_bind = bind_types[idx_bind]
                sel_mods = modifier_opts[idx_mod]
                sel_key = key_opts[idx_key]
                if 0 <= idx_app < len(apps):
                    sel_exec = apps[idx_app][1]
                else:
                    sel_exec = cur_app
                # Construct rhs: modifiers, key, exec
                rhs_parts = []
                if sel_mods:
                    rhs_parts.append(sel_mods)
                rhs_parts.append(sel_key)
                rhs = ", ".join(rhs_parts)
                rhs = f"{rhs}, exec, {sel_exec}" if sel_exec else f"{rhs}"
                new_line = f"{sel_bind} = {rhs}"
                self.model.edit(self.cursor, new_line)
                self.status = f"Saved bind on line {self.cursor + 1}"
                del win
                return
            elif ch in (27,):  # ESC
                del win
                self.status = "Canceled"
                return
            else:
                # ignore
                pass

    def run(self):
        while True:
            self.draw()
            self.height, self.width = self.stdscr.getmaxyx()
            ch = self.stdscr.getch()
            if ch == curses.KEY_MOUSE:
                try:
                    _, x, y, _, bstate = curses.getmouse()
                    if bstate & curses.BUTTON1_PRESSED:  # Left click
                        file_idx = self._screen_to_file_map.get(y)
                        if file_idx is not None:
                            self.cursor = file_idx
                except curses.error:
                    # Mouse event outside window, ignore
                    pass
            elif ch in (curses.KEY_UP, ord("k")):
                if self.cursor > 0:
                    self.cursor -= 1
            elif ch in (curses.KEY_DOWN, ord("j")):
                if self.cursor < max(len(self.model.lines) - 1, 0):
                    self.cursor += 1
            elif ch == curses.KEY_NPAGE:
                self.cursor = min(
                    len(self.model.lines) - 1, self.cursor + (self.height // 2)
                )
            elif ch == curses.KEY_PPAGE:
                self.cursor = max(0, self.cursor - (self.height // 2))
            elif ch in (ord("\n"), ord("\r"), ord("e")):
                self.structured_edit_bind_column()
            elif ch == ord("a"):
                new = self.prompt("Add line (insert after current)", "")
                if new:
                    if self.model.lines:
                        self.model.insert_after(self.cursor, new)
                        self.cursor += 1
                    else:
                        self.model.append(new)
                        self.cursor = 0
                    self.status = "Inserted line"
            elif ch == ord("d"):
                if not self.model.lines:
                    self.status = "Nothing to delete"
                else:
                    if self.confirm(f"Delete line {self.cursor + 1}?"):
                        self.model.delete(self.cursor)
                        if self.cursor >= len(self.model.lines):
                            self.cursor = max(0, len(self.model.lines) - 1)
                        self.status = "Deleted"
            elif ch == ord("t"):
                if self.model.lines:
                    self.model.toggle(self.cursor)
                    self.status = "Toggled enable/disable"
            elif ch == ord("u"):
                if self.model.lines:
                    self.cursor = self.model.move_up(self.cursor)
            elif ch == ord("m"):
                if self.model.lines:
                    self.cursor = self.model.move_down(self.cursor)
            elif ch == ord("s"):
                try:
                    self.model.save()
                    self.status = f"Saved {self.model.path} (backup created)"
                except Exception as e:
                    self.status = f"Error saving: {e}"
            elif ch == ord("b"):
                try:
                    dst = backup_file(self.model.path)
                    self.status = f"Backup created: {dst}"
                except Exception as e:
                    self.status = f"Backup error: {e}"
            elif ch in (ord("h"), ord("?")):
                self.show_help()
            elif ch == 9:  # TAB
                self.switch()
            elif ch == ord("q"):
                if self.model.dirty:
                    if self.confirm("Unsaved changes. Save before quit?"):
                        try:
                            self.model.save()
                            self.status = "Saved"
                        except Exception as e:
                            self.status = f"Save failed: {e}"
                            continue
                break
            else:
                # ignore other keys
                pass

    def confirm(self, msg: str) -> bool:
        curses.curs_set(1)
        self.stdscr.addnstr(self.height - 2, 0, msg + " (y/n) ", self.width)
        self.stdscr.refresh()
        while True:
            ch = self.stdscr.getch()
            if ch in (ord("y"), ord("Y")):
                curses.curs_set(0)
                return True
            if ch in (ord("n"), ord("N")):
                curses.curs_set(0)
                return False

    def show_help(self):
        h = curses.newwin(14, self.width - 4, 2, 2)
        h.border()
        lines = [
            "Hypr Settings TUI - Help",
            "",
            "Navigation:",
            "  Up/Down: move between file lines",
            "  Enter: open column editor for a bind line",
            "",
            "Category headings:",
            "  Add a comment line starting with '# Category: <name>' to create sections",
            "  The listing will group/label lines by these headings (no line numbers shown)",
            "",
            "Column editor keys (when open):",
            "  Left/Right: switch column",
            "  Up/Down: cycle values",
            "  Enter: open chooser for column",
            "  c: input custom value for column",
            "  s: save changes (applies to file model)",
            "  Esc: cancel editor",
            "",
            "Other:",
            "  s: save file (from main screen)",
            "  q: quit (prompts to save if modified)",
        ]
        for i, ln in enumerate(lines):
            try:
                h.addnstr(1 + i, 1, ln, self.width - 6)
            except curses.error:
                pass
        h.getch()
        del h

    def switch(self):
        other = "autostart" if self.model_name == "keybinds" else "keybinds"
        self.model_name = other
        self.model = LineList(FILES[other])
        self.cursor = 0
        self.top = 0
        self.status = f"Switched to {other}"


def main():
    ensure_paths()
    import argparse

    parser = argparse.ArgumentParser(
        description="Hypr settings TUI (keybinds/autostart)"
    )
    parser.add_argument(
        "file",
        choices=["keybinds", "autostart"],
        nargs="?",
        default="keybinds",
        help="which file to edit (keybinds or autostart)",
    )
    args = parser.parse_args()

    def curses_main(stdscr):
        ui = Tui(stdscr, args.file)
        ui.run()

    curses.wrapper(curses_main)


if __name__ == "__main__":
    main()
