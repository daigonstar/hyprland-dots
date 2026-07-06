#!/usr/bin/env bash
# Rofi keybind cheatsheet.
# Parses keybinds.conf (via generate.sh) and displays it as a readable,
# categorized list in rofi -dmenu, matching the format used by the
# hypr settings TUI (Type/Modifiers/Key => Action, grouped by "# Category:").

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Escape pango markup special characters so future keybind actions
# containing &, <, > don't break rendering.
esc() {
    local s="$1"
    s="${s//&/&amp;}"
    s="${s//</&lt;}"
    s="${s//>/&gt;}"
    printf '%s' "$s"
}

build_list() {
    while IFS=$'\x01' read -r kind a b c; do
        case "$kind" in
            HEAD)
                printf '<b><u>%s</u></b>\n' "$(esc "$a")"
                printed_any=1
                ;;
            BIND)
                mods="$a"; key="$b"; action="$c"
                combo="$mods"
                if [[ -n "$combo" && -n "$key" ]]; then
                    combo="$combo + $key"
                elif [[ -z "$combo" ]]; then
                    combo="$key"
                fi
                printf '  <b>%-22s</b>  →  %s\n' "$(esc "$combo")" "$(esc "$action")"
                printed_any=1
                ;;
        esac
    done < <("$DIR/generate.sh")
}

build_list | rofi -dmenu \
    -markup-rows \
    -p "Keybinds" \
    -theme "$DIR/style.rasi" \
    > /dev/null
