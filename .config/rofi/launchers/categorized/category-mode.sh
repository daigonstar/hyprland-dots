#!/usr/bin/env bash
#
## Rofi script-mode handler for one category tab.
## Invoked by rofi as: category-mode.sh "<Bucket Name>" [selected-app-name]
## The bucket name is baked in via the -modi mapping built by launcher.sh;
## rofi appends the selected row's text as an extra argument once the user
## picks an app (see `man rofi-script`).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/applist.sh"

bucket="$1"

if [[ "${ROFI_RETV:-0}" == "1" ]]; then
    # An app was selected; ROFI_INFO carries the desktop file id we attached
    # via the "info" row option in print_rofi_entries_for_bucket().
    if [[ -n "${ROFI_INFO:-}" ]]; then
        # Launch detached so rofi doesn't block waiting on its output, then
        # print nothing so rofi closes (per rofi-script(5): "If the script
        # returns no entries, rofi quits.").
        coproc ( gtk-launch "$ROFI_INFO" >/dev/null 2>&1 )
    fi
    exit 0
fi

print_rofi_entries_for_bucket "$bucket"
