#!/usr/bin/env bash
sleep 1
# 1. Kill everything portal-related
killall -9 xdg-desktop-portal-hyprland
killall -9 xdg-desktop-portal-gtk
killall -9 xdg-desktop-portal

# 2. Update environment for D-Bus
dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=Hyprland
systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP

# 3. Start the binaries directly (NOT via systemctl)
/usr/lib/xdg-desktop-portal-hyprland &
sleep 2
/usr/lib/xdg-desktop-portal &
