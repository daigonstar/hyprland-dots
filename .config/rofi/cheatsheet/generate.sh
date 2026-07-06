#!/usr/bin/env bash
# Parses ~/.config/hypr/keybinds.conf and emits a rofi -dmenu compatible list
# (pango markup rows), grouped under "# Category: ..." headings, in the same
# spirit as the hypr settings TUI (settings/tui.py) table view:
#   Type | Modifiers | Key  =>  Action args
# Category headings are rendered bold+underlined; bind rows show the key
# combo (with $variables like $mainMod resolved) followed by the action.

KEYBINDS="$HOME/.config/hypr/keybinds.conf"

gawk -v RS='\n' '
BEGIN {
    FS = "\n";
}

# ---- Pass 1 happens inline as we read top-to-bottom: variable assignment
# lines ($name = value) are recorded into a substitution map as soon as we
# see them, which matches how Hyprland itself resolves them (in order).
function trim(s) {
    gsub(/^[ \t]+|[ \t]+$/, "", s);
    return s;
}

{
    line = $0;
    stripped = trim(line);

    # Variable assignment: $name = value
    if (match(stripped, /^\$([A-Za-z_][A-Za-z0-9_]*)[ \t]*=[ \t]*(.*)$/, m)) {
        vars[m[1]] = trim(m[2]);
        next;
    }

    # Category heading
    if (tolower(stripped) ~ /^# *category:/) {
        sub(/^# *[Cc]ategory:[ \t]*/, "", stripped);
        # emit heading row
        printf("HEAD\x01%s\n", stripped);
        next;
    }

    # Skip blank lines and other comments
    if (stripped == "" || stripped ~ /^#/) next;

    # Pull off a trailing "# comment" (the human-readable description) before
    # doing anything else with the line, so it never gets mixed into the
    # parsed action/args.
    comment = "";
    if (match(stripped, /#.*$/)) {
        comment = trim(substr(stripped, RSTART + 1));
        stripped = trim(substr(stripped, 1, RSTART - 1));
    }

    # Bind lines: bind/bindm/binde/bindl/bindel = mods, key, action, args...
    if (match(stripped, /^(bind[a-z]*)[ \t]*=[ \t]*(.*)$/, m)) {
        btype = m[1];
        rest = m[2];

        # split rest into up to 4 comma separated parts (mods,key,action,remainder)
        n = split(rest, parts, ",");
        mods = (n >= 1) ? trim(parts[1]) : "";
        key  = (n >= 2) ? trim(parts[2]) : "";
        action = (n >= 3) ? trim(parts[3]) : "";
        remainder = "";
        if (n >= 4) {
            remainder = parts[4];
            for (i = 5; i <= n; i++) remainder = remainder "," parts[i];
            remainder = trim(remainder);
        }

        # resolve $variables token-by-token in mods
        nm = split(mods, modtoks, /[ \t]+/);
        modstr = "";
        for (i = 1; i <= nm; i++) {
            tok = modtoks[i];
            if (tok ~ /^\$/) {
                vname = substr(tok, 2);
                if (vname in vars) tok = vars[vname];
            }
            modstr = (modstr == "") ? tok : modstr " + " tok;
        }

        # resolve $variables anywhere within key/action/remainder
        keyr = key;
        if (keyr ~ /^\$/) {
            vname = substr(keyr, 2);
            if (vname in vars) keyr = vars[vname];
        }

        # Prefer the human-written "# comment" as the description shown in
        # the cheatsheet; fall back to the raw resolved action if a bind
        # has no comment yet.
        if (comment != "") {
            actionfull = comment;
        } else {
            actionfull = trim(action " " remainder);
            # replace every $token that matches a known var, globally
            for (v in vars) {
                pat = "\\$" v "([^A-Za-z0-9_]|$)";
                while (match(actionfull, pat)) {
                    pre = substr(actionfull, 1, RSTART - 1);
                    matched = substr(actionfull, RSTART, RLENGTH);
                    suffix_char = substr(matched, length(matched), 1);
                    # keep trailing non-var char (could be end of string)
                    if (suffix_char ~ /[A-Za-z0-9_]/) suffix_char = "";
                    post = substr(actionfull, RSTART + RLENGTH);
                    actionfull = pre vars[v] suffix_char post;
                }
            }
            if (actionfull == "") actionfull = "(none)";
        }

        printf("BIND\x01%s\x01%s\x01%s\n", modstr, keyr, actionfull);
        next;
    }
}
' "$KEYBINDS"
