#!/bin/bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */
# Optimized for Multi-Monitor Sync and Wallust 3.0

# WALLPAPERS PATH
terminal=kitty
wallDIR="$HOME/Pictures/wallpapers"
SCRIPTSDIR="$HOME/.config/hypr/scripts"
wallpaper_current="$HOME/.config/rofi/wallpaper/.wallpaper_current"

# Directory for rofi/swaync
iDIR="$HOME/.config/rofi/images"
iDIRi="$HOME/.config/rofi/icons"

# swww transition config
FPS=60
TYPE="any"
DURATION=2
BEZIER=".43,1.19,1,.4"
SWWW_PARAMS="--transition-fps $FPS --transition-type $TYPE --transition-duration $DURATION --transition-bezier $BEZIER"

# Check if package bc exists
if ! command -v bc &>/dev/null; then
  notify-send -i "$iDIR/error.png" "bc missing" "Install package bc first"
  exit 1
fi

# Variables
rofi_theme="$HOME/.config/rofi/wallpaper/wallpaper.rasi"
focused_monitor=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')

# Ensure focused_monitor is detected
if [[ -z "$focused_monitor" ]]; then
  focused_monitor=$(hyprctl monitors -j | jq -r '.[0].name')
fi

# Monitor details for Rofi scaling
scale_factor=$(hyprctl monitors -j | jq -r --arg mon "$focused_monitor" '.[] | select(.name == $mon) | .scale')
monitor_height=$(hyprctl monitors -j | jq -r --arg mon "$focused_monitor" '.[] | select(.name == $mon) | .height')

icon_size=$(echo "scale=1; ($monitor_height * 3) / ($scale_factor * 150)" | bc)
adjusted_icon_size=$(echo "$icon_size" | awk '{if ($1 < 15) $1 = 20; if ($1 > 25) $1 = 25; print $1}')
rofi_override="element-icon{size:${adjusted_icon_size}%;}"

# Kill existing wallpaper daemons
kill_wallpaper_for_video() {
  swww kill 2>/dev/null
  pkill mpvpaper 2>/dev/null
  pkill swaybg 2>/dev/null
  pkill hyprpaper 2>/dev/null
}

kill_wallpaper_for_image() {
  pkill mpvpaper 2>/dev/null
  pkill swaybg 2>/dev/null
  pkill hyprpaper 2>/dev/null
}

# Retrieve wallpapers
mapfile -d '' PICS < <(find -L "${wallDIR}" -type f \( \
  -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o \
  -iname "*.bmp" -o -iname "*.tiff" -o -iname "*.webp" -o \
  -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.mov" -o -iname "*.webm" \) -print0)

RANDOM_PIC="${PICS[$((RANDOM % ${#PICS[@]}))]}"
RANDOM_PIC_NAME=". random"

# Rofi command
rofi_command="rofi -i -show -dmenu -config $rofi_theme -theme-str $rofi_override"

# Sorting Wallpapers
menu() {
  IFS=$'\n' sorted_options=($(sort <<<"${PICS[*]}"))
  printf "%s\x00icon\x1f%s\n" "$RANDOM_PIC_NAME" "$RANDOM_PIC"
  for pic_path in "${sorted_options[@]}"; do
    pic_name=$(basename "$pic_path")
    if [[ "$pic_name" =~ \.gif$ ]]; then
      printf "%s\x00icon\x1f%s\n" "$pic_name" "$pic_path"
    else
      printf "%s\x00icon\x1f%s\n" "$(echo "$pic_name" | cut -d. -f1)" "$pic_path"
    fi
  done
}

# Apply Image Wallpaper (Syncs All Monitors)
apply_image_wallpaper() {
  local image_path="$1"
  kill_wallpaper_for_image

  if ! pgrep -x "swww-daemon" >/dev/null; then
    swww-daemon --format xrgb &
    sleep 0.5
  fi

  # Apply to ALL monitors by removing the -o flag
  swww img "$image_path" $SWWW_PARAMS

  # Run wallust and pass the path directly
  if [ -f "$SCRIPTSDIR/wallust.sh" ]; then
    bash "$SCRIPTSDIR/wallust.sh" "$image_path"
  fi

  # Refresh other components (Waybar/SwayNC)
  if [ -f "$SCRIPTSDIR/refresh.sh" ]; then
    bash "$SCRIPTSDIR/refresh.sh"
  fi
}

apply_video_wallpaper() {
  local video_path="$1"
  if ! command -v mpvpaper &>/dev/null; then
    notify-send "mpvpaper not found"
    return 1
  fi
  kill_wallpaper_for_video
  mpvpaper '*' -o "load-scripts=no no-audio --loop" "$video_path" &
}

# Main function
main() {
  choice=$(menu | $rofi_command)
  if [[ -z "$choice" ]]; then
    exit 0
  fi

  if [[ "$choice" == "$RANDOM_PIC_NAME" ]]; then
    selected_file="$RANDOM_PIC"
  else
    # Find the full path of the selected file
    choice_basename=$(basename "$choice")
    selected_file=$(find "$wallDIR" -iname "$choice_basename*" -print -quit)
  fi

  if [[ -z "$selected_file" ]]; then
    exit 1
  fi

  if [[ "$selected_file" =~ \.(mp4|mkv|mov|webm|MP4|MKV|MOV|WEBM)$ ]]; then
    apply_video_wallpaper "$selected_file"
  else
    apply_image_wallpaper "$selected_file"
  fi
}

if pidof rofi >/dev/null; then
  pkill rofi
fi

main