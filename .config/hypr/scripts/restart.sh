#!/usr/bin/env bash
case "$1" in
    swaync)
        pkill swaync || true
        sleep 0.1
        swaync &
        ;;
    waybar)
        pkill waybar || true
        sleep 0.1
        waybar &
        ;;
    all|"")
        pkill swaync || true
        pkill waybar || true
        sleep 0.2
        waybar &
        swaync &
        ;;
esac
