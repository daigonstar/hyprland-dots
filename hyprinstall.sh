#!/usr/bin/env bash

#

# hyprinstall-final.sh

# Production-ready Hyprland setup installer

# Options: --dry-run, --verbose

# Logging: ~/.local/share/hyprinstall/hyprinstall.log

set -euo pipefail

# Configuration defaults

DEFAULT_LOG="$HOME/.local/share/hyprinstall/hyprinstall.log"
FALLBACK_LOG="$HOME/hyprinstall.log"
REPO_DIR="$HOME/hyprdots"
DOTFILES_DIR="$REPO_DIR/.config"
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQUIRED_FILE="$BASE_DIR/required.txt"
NVIDIA_FILE="$BASE_DIR/nvidia.txt"
FLATPAK_FILE="$BASE_DIR/flatpak.txt"
LOGFILE="$DEFAULT_LOG"
EXTRA_DEPENDENCIES=(git base-devel flatpak python rust imagemagick rsync)

# Parse flags

DRY_RUN=false
VERBOSE=false
for arg in "$@"; do
case "$arg" in
--dry-run) DRY_RUN=true ;;
--verbose) VERBOSE=true ;;
esac
done
# Logging helpers

init_logging() {
if [[ "$DRY_RUN" == "true" ]]; then
echo "[DRY RUN] Would initialize logging to $LOGFILE"
return
fi
if touch "$DEFAULT_LOG" >/dev/null 2>&1; then
LOGFILE="$DEFAULT_LOG"
else
LOGFILE="$FALLBACK_LOG"
mkdir -p "$(dirname "$LOGFILE")"
touch "$LOGFILE"
echo "Note: couldn't write to $DEFAULT_LOG; using $LOGFILE"
fi
}

log() {
local level="$1"; shift
local ts
ts="$(date +'%Y-%m-%d %H:%M:%S')"
printf "%s [%s] %s\n" "$ts" "$level" "$*" | tee -a "$LOGFILE"
}

die() {
log "ERROR" "$*"
exit 1
}

# Command runner

run_cmd() {
local cmd="$*"
if [[ "$DRY_RUN" == "true" ]]; then
printf "[DRY RUN] %s\n" "$cmd" | tee -a "$LOGFILE"
return
fi


if [[ "$VERBOSE" == "true" ]]; then
    log "CMD" "$cmd"
    bash -c "$cmd" 2>&1 | tee -a "$LOGFILE"
    return ${PIPESTATUS[0]}
fi

local out
out=$(mktemp)
bash -c "$cmd" >"$out" 2>&1 &
local pid=$!
local dots=( "   " "*  " "** " "***" )
local i=0
while kill -0 "$pid" 2>/dev/null; do
    printf "\r%s" "${dots[i]}"
    i=$(( (i + 1) % ${#dots[@]} ))
    sleep 0.5
done
wait "$pid"
local st=$?
printf "\r   \r"
if [[ $st -eq 0 ]]; then
    log "OK" "$cmd"
    rm -f "$out"
else
    log "FAIL" "$cmd (exit $st)"
    log "FAIL" "Command output (first 200 lines):"
    sed -n '1,200p' "$out" | sed "s/^/    /" >> "$LOGFILE"
    rm -f "$out"
    return $st
fi

}

# Utility functions

read_packages_to_array() {
local file="$1"
local -n arr=$2
arr=()
if [[ -f "$file" ]]; then
while IFS= read -r line; do
line="${line%%#*}"
line="$(echo "$line" | xargs)"
[[ -z "$line" ]] && continue
arr+=("$line")
done < "$file"
fi
}

yesno_prompt() {
local prompt="$1"
local default="${2:-N}"
if [[ "$DRY_RUN" == "true" ]]; then
printf "[DRY RUN] %s (default %s) -> No\n" "$prompt" "$default"
return 1
fi
read -rp "$prompt [$default]: " ans
[[ -z "$ans" ]] && ans="$default"
[[ "$ans" =~ ^[Yy] ]]
}

# Script start

init_logging
log "INFO" "Starting hyprinstall-final. Log: $LOGFILE"

# Branch selection for repo operations (supports UPDATE_BRANCH env var or .update-branch file)
BRANCH="${UPDATE_BRANCH:-}"
if [[ -f "$BASE_DIR/.update-branch" ]]; then
  BRANCH="$(<$BASE_DIR/.update-branch)"
fi
if [[ -z "$BRANCH" && "$DRY_RUN" == "false" && -t 0 ]]; then
  echo "Select branch to use for repo operations:"
  echo "  1) main (end users)"
  echo "  2) dev (development)"
  echo "  3) Enter branch name"
  read -rp "Choice [1-3] (default 2): " _choice
  case "$_choice" in
    1) BRANCH="main" ;;
    3) read -rp "Enter branch name: " BRANCH ;;
    *) BRANCH="dev" ;;
  esac
fi
BRANCH="${BRANCH:-dev}"
log "INFO" "Using branch: $BRANCH"

# If repo exists and is a git repo, attempt to check it out and update to the selected branch
if git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  run_cmd "git -C \"$REPO_DIR\" fetch --prune origin"
  # Best-effort checkout and pull; do not abort installer if these fail
  run_cmd "git -C \"$REPO_DIR\" checkout \"$BRANCH\"" || true
  run_cmd "git -C \"$REPO_DIR\" pull --ff-only origin \"$BRANCH\"" || true
fi

# Install core dependencies

log "INFO" "Ensuring extra dependencies: ${EXTRA_DEPENDENCIES[*]}"
for d in "${EXTRA_DEPENDENCIES[@]}"; do
if pacman -Qi "$d" &>/dev/null; then
log "OK" "Dependency present: $d"
else
run_cmd "sudo pacman -S --needed --noconfirm \"$d\""
fi
done

# Read package lists

read_packages_to_array "$REQUIRED_FILE" REQUIRED_PKGS
read_packages_to_array "$NVIDIA_FILE" NVIDIA_PKGS
read_packages_to_array "$FLATPAK_FILE" FLATPAK_PKGS

# Install paru (AUR helper)

install_paru() {
if command -v paru >/dev/null 2>&1; then
log "OK" "paru already installed"
return
fi
run_cmd "sudo pacman -S --needed --noconfirm git base-devel"
local tmpdir
tmpdir="$(mktemp -d)"
run_cmd "git clone https://aur.archlinux.org/paru.git "$tmpdir/paru""
pushd "$tmpdir/paru" >/dev/null
run_cmd "makepkg -si --noconfirm"
popd >/dev/null
rm -rf "$tmpdir"
log "OK" "paru installed"
}
install_paru

# Install required packages

install_package_list() {
local pkgs=("$@")
for pkg in "${pkgs[@]:-}"; do
if pacman -Qq "$pkg" &>/dev/null; then
log "OK" "Package $pkg already installed"
else
if command -v paru >/dev/null 2>&1; then
run_cmd "paru -S --noconfirm "$pkg"" || run_cmd "sudo pacman -S --noconfirm "$pkg""
else
run_cmd "sudo pacman -S --noconfirm "$pkg""
fi
fi
done
}

install_package_list "${REQUIRED_PKGS[@]}"

# Flatpak installs

for f in "${FLATPAK_PKGS[@]:-}"; do
if flatpak list --app | grep -qw "$f"; then
log "OK" "Flatpak $f already installed"
else
run_cmd "flatpak install -y --noninteractive --or-update flathub "$f""
fi
done

# NVIDIA packages (optional)

if [[ ${#NVIDIA_PKGS[@]} -gt 0 ]]; then
if yesno_prompt "Install NVIDIA packages?"; then
install_package_list "${NVIDIA_PKGS[@]}"
fi
fi

# Home directories

run_cmd "mkdir -p \"$HOME/Pictures\" \"$HOME/Videos\" \"$HOME/Documents\" \"$HOME/.config\" \"$HOME/Downloads\""

# Backup existing config (optional)

BACKUP_YES=false
if yesno_prompt "Back up existing config directories?"; then
    BACKUP_DIR="$HOME/.config-backup"
    run_cmd "mkdir -p \"$BACKUP_DIR\""
    BACKUP_YES=true
fi

# Symlink config directories

CONFIG_TARGETS=(hypr fastfetch rofi waybar swaync wallust ghostty hypr-dock)
for dir in "${CONFIG_TARGETS[@]}"; do
target="$HOME/.config/$dir"
source="$DOTFILES_DIR/$dir"
if [[ ! -d "$source" ]]; then
log "WARN" "Source missing: $source"
continue
fi
if [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then
log "OK" "Already symlinked: $target"
continue
fi
[[ -e "$target" ]] && [[ "$BACKUP_YES" == "true" ]] && run_cmd cp -r "$target" "$BACKUP_DIR/"
run_cmd rm -rf "$target"
run_cmd ln -sfn "$source" "$target"
done

# Add temp monitor and worspace configs

run_cmd touch "$HOME/.config/hypr/monitors.conf"
run_cmd touch "$HOME/.config/hypr/workspaces.conf"

# Starship config

starship_file="$HOME/.config/starship.toml"
[[ -e "$starship_file" ]] && run_cmd rm "$starship_file"
run_cmd ln -sfn "$DOTFILES_DIR/starship.toml" "$starship_file"

# Wallpapers

wallpaper_src="$REPO_DIR/wallpapers"
wallpaper_dest="$HOME/Pictures/wallpapers"
[[ -e "$wallpaper_dest" ]] && run_cmd rm -rf "$wallpaper_dest"
[[ -d "$wallpaper_src" ]] && run_cmd cp -r "$wallpaper_src" "$wallpaper_dest"

# Make scripts executable

SCRIPT_FILES=(hypr/scripts/ai.sh hypr/scripts/browser.sh hypr/scripts/gamemode.sh hypr/scripts/pywall.sh hypr/scripts/rainbowb.sh hypr/scripts/refresh.sh hypr/scripts/wallust.sh rofi/powermenu/powermenu.sh rofi/launchers/launcher.sh rofi/wallpaper/wallpaper.sh)
for s in "${SCRIPT_FILES[@]}"; do
sp="$DOTFILES_DIR/$s"
[[ -f "$sp" ]] && run_cmd "chmod +x "$sp""
done

# Cursor icons + Flatpak overrides

if [[ -d "$REPO_DIR/icons/Future-cursors" ]]; then
run_cmd "sudo cp -r \"$REPO_DIR/icons/Future-cursors\" /usr/share/icons/Future-cursors"
run_cmd "flatpak --user override --filesystem=/home/\"$USER\"/.icons/:ro"
run_cmd "flatpak --user override --filesystem=/usr/share/icons/:ro"
fi

# Bashrc update

BASHRC_MARKER="# --- hyprinstall additions BEGIN ---"
if ! grep -Fq "$BASHRC_MARKER" "$HOME/.bashrc" 2>/dev/null; then
cat >> "$HOME/.bashrc" <<EOF

# --- hyprinstall additions BEGIN ---

alias update='paru -Syu && flatpak update'
alias hyprupdate="$HOME/hyprdots/update.sh"
eval "$(starship init bash)"
command fastfetch

# --- hyprinstall additions END ---

EOF
log "OK" "Appended hyprinstall additions to ~/.bashrc"
else
log "INFO" "~/.bashrc already contains hyprinstall additions; skipping"
fi

# If the bashrc update included the DisplayPort xrandr line, ensure SDDM's
# Xsetup also contains the necessary xrandr commands so the display is set
# correctly at the greeter/session start.
XSETUP_FILE="/usr/share/sddm/scripts/Xsetup"
XRANDR_LINE1='xrandr --output DisplayPort-0 --primary'
XRANDR_LINE2='xrandr --output HDMI-2 --off'
if grep -qF "$XRANDR_LINE1" "$HOME/.bashrc" 2>/dev/null; then
    run_cmd "sudo cp \"$XSETUP_FILE\" \"$XSETUP_FILE.bak\""
    run_cmd "sudo bash -c 'grep -q -F \"$XRANDR_LINE1\" \"$XSETUP_FILE\" || cat >> \"$XSETUP_FILE\" <<EOF
$XRANDR_LINE1
$XRANDR_LINE2
EOF'"
    run_cmd "sudo chmod +x \"$XSETUP_FILE\""
    log "OK" "Ensured xrandr lines present in $XSETUP_FILE (backup created)."
else
    log "INFO" "Skipping adding xrandr lines to $XSETUP_FILE; ~/.bashrc lacks marker."
fi

# Hide unwanted apps from launcher

echo "🔧 Hiding unwanted apps from launcher..."
APPS_FILE="$HOME/hyprdots/hide.txt"

if [[ ! -f "$APPS_FILE" ]]; then
    echo "❌ App list file not found: $APPS_FILE. Skipping app hiding."
else
  while IFS= read -r app; do
      [[ -z "$app" || "$app" =~ ^# ]] && continue
      desktop_file="/usr/share/applications/$app.desktop"
      user_desktop_file="$HOME/.local/share/applications/$app.desktop"

      echo "Processing app '$app' for hiding..."
      if [[ -f "$desktop_file" ]]; then
          run_cmd "mkdir -p \"$HOME/.local/share/applications\""
          run_cmd "cp \"$desktop_file\" \"$user_desktop_file\""
          if grep -q '^NoDisplay=true' "$user_desktop_file"; then
              echo "✅ App '$app' is already hidden."
          else
              echo "Hiding '$app.desktop'"
              run_cmd "echo \"NoDisplay=true\" >> \"$user_desktop_file\""
          fi
      else
          echo "Could not find desktop file: '$desktop_file', skipping hiding for '$app'."
      fi
  done < "$APPS_FILE"
fi

#Git Setup



# SDDM Configuration

echo "enabling SDDM"
run_cmd "sudo systemctl enable sddm.service"

echo "🎨 Installing SDDM theme..."
run_cmd "sudo cp -R $REPO_DIR/SDDM/sugar-dark /usr/share/sddm/themes"
run_cmd "sudo mkdir -p /etc/sddm.conf.d" # Ensure directory exists
run_cmd "sudo cp $REPO_DIR/SDDM/sddm.conf /etc/sddm.conf.d/sddm.conf"

# Plymouth Configuration

run_cmd "sudo git clone https://github.com/krishnan793/PlymouthTheme-Cat.git /usr/share/plymouth/themes/PlymouthTheme-Cat"
run_cmd "sudo plymouth-set-default-theme PlymouthTheme-Cat -R"

log "INFO" "DaigonStar Hyprdots setup completed."
echo "DaigonStar Hyprdots setup completed."
sleep 3
echo "Restarting SDDM to apply changes..."
sleep 2
sudo systemctl restart sddm

exit 0
