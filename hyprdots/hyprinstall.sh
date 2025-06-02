#!/bin/bash

set -e

# Enable dry run mode with --dry-run
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
  DRY_RUN=true
  echo "🧪 Dry run mode enabled. No changes will be made."
fi
VERBOSE=false
for arg in "$@"; do
  [[ "$arg" == "--verbose" ]] && VERBOSE=true
done
# Helper to run or simulate commands
run_cmd() {
  if $DRY_RUN; then
    echo "[DRY RUN] $*"
  else
    if $VERBOSE; then
      echo "[VERBOSE] $*"
      bash -c "$@"
    else
      bash -c "$@" > /dev/null 2>&1 &
      pid=$!
      while kill -0 $pid 2>/dev/null; do
        echo -n "."
        sleep 0.7
      done
      wait $pid
      echo " done"
    fi
  fi
}

# Function to read package list from file
read_packages() {
  local file="$1"
  if [[ -f "$file" ]]; then
    tr '\n' ' ' < "$file"
  else
    echo "❌ Error: $file not found" >&2
    exit 1
  fi
}

# Read package lists
req=$(read_packages "required.txt")
nvidia=$(read_packages "nvidia.txt")
flatpak=$(read_packages "$HOME/hyprland-dots/hyprdots/flatpak.txt")
# Install git and paru

echo "📦 Installing git and paru..."
run_cmd "sudo pacman -Syu --noconfirm git"

if [[ ! -d "paru" ]]; then
  run_cmd "git clone https://aur.archlinux.org/paru.git"
fi

if [[ -d "paru" ]]; then
  cd paru || exit
  run_cmd "makepkg -si --noconfirm"
  cd ..
fi

echo "✅ Paru installed."

# Install required packages
echo "📦 Installing required packages..."
run_cmd "paru -S --noconfirm $req"

# Install flatpak packages
echo "📦 Installing flatpak packages..."
while IFS= read -r pkg; do
  [[ -z "$pkg" || "$pkg" =~ ^# || "$pkg" =~ ^// ]] && continue
  flatpak install -y --noninteractive --or-update flathub "$pkg"
done < "$HOME/hyprland-dots/hyprdots/flatpak.txt"

# Enable flatpak services
run_cmd "flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo"

# NVIDIA packages
echo "NVIDIA packages: $nvidia"
read -rp "Install NVIDIA packages? [y/N]: " install_nvidia
if [[ "$install_nvidia" =~ ^[Yy]$ ]]; then
  run_cmd "paru -S --noconfirm $nvidia"
fi

# Install Dual Boot tools
echo "📦 Dual Boot"
read -rp "Do you want to install refind? [y/N]: " install_dual_boot
if [[ "$install_dual_boot" =~ ^[Yy]$ ]]; then

  run_cmd "sudo pacman -S --noconfirm refind"
  echo "Installing rEFInd..."
  run_cmd "sudo refind-install"
  run_cmd "sudo mkdir -p /boot/EFI/refind/themes"
  run_cmd "sudo git clone https://github.com/catppuccin/refind.git /boot/EFI/refind/themes/catppuccin"
  echo 'include themes/catppuccin/mocha.conf' | sudo tee -a /boot/EFI/refind/refind.conf > /dev/null
else
  echo "Skipping rEFInd installation."
fi

# Copy config directories
dotfiles_dir=~/hyprland-dots/hyprdots/.config
config_targets=(hypr fastfetch rofi waybar swaync wallust)
gitdir=~/hyprland-dots/hyprdots

run_cmd "mkdir -p ~/.config"

# Ask user about backup
read -rp "Do you want to back up your existing config directories before replacing them? [y/N]: " backup_configs
if [[ "$backup_configs" =~ ^[Yy]$ ]]; then
  backup_dir="$HOME/.config-backup-$(date +%Y%m%d%H%M%S)"
  mkdir -p "$backup_dir"
  echo "Backing up configs to $backup_dir"
fi

for dir in "${config_targets[@]}"; do
  target="$HOME/.config/$dir"
  source="$dotfiles_dir/$dir"

  if [[ -d "$target" || -L "$target" ]]; then
    if [[ "$backup_configs" =~ ^[Yy]$ ]]; then
      echo "Backing up $target to $backup_dir/"
      run_cmd "cp -r \"$target\" \"$backup_dir/\""
    fi
    echo "Removing existing config: $target"
    run_cmd "rm -rf \"$target\""
  fi

  if [[ -d "$source" ]]; then
    echo "Symlinking $source to $target"
    run_cmd "ln -sfn \"$source\" \"$target\""

    # Starship config
    if [[ -e "$HOME/.config/starship.toml" || -L "$HOME/.config/starship.toml" ]]; then
      run_cmd "rm \"$HOME/.config/starship.toml\""
    fi
    run_cmd "ln -sfn \"$dotfiles_dir/starship.toml\" \"$HOME/.config/starship.toml\""

    # Wallpapers
        if [[ -e "$HOME/Pictures/wallpapers" || -L "$HOME/Pictures/wallpapers" ]]; then
            run_cmd "rm -rf \"$HOME/Pictures/wallpapers\""
        fi
        if [[ -d "$gitdir/hyprdots/wallpapers" ]]; then
            run_cmd "cp -r \"$gitdir/hyprdots/wallpapers\" \"$HOME/Pictures/wallpapers\""
        else
            echo "⚠️ Warning: $gitdir/hyprdots/wallpapers does not exist, skipping wallpapers copy."
        fi
   
done


# Enable scripts
echo "🔧 Enabling scripts..."
chmod +x $dotfiles_dir/hypr/scripts/ai.sh
chmod +x $dotfiles_dir/hypr/scripts/browser.sh
chmod +x $dotfiles_dir/hypr/scripts/gamemode.sh
chmod +x $dotfiles_dir/hypr/scripts/pywall.sh
chmod +x $dotfiles_dir/hypr/scripts/rainbowb.sh
chmod +x $dotfiles_dir/hypr/scripts/refresh.sh
chmod +x $dotfiles_dir/hypr/scripts/wallust.sh
chmod +x $dotfiles_dir/rofi/powermenu/powermenu.sh
chmod +x $dotfiles_dir/rofi/launchers/launcher.sh
chmod +x $dotfiles_dir/rofi/wallpaper/wallpaper.sh

# Install cursor
echo "Installing cursor"
run_cmd "sudo cp -r "$gitdir/icons/Future-cursors" /usr/share/icons"

flatpak --user override --filesystem=/home/$USER/.icons/:ro
flatpak --user override --filesystem=/usr/share/icons/:ro 


# Bashrc
echo "🔧 Updating .bashrc with aliases and startup commands..."
bashrc_addition=$(cat <<'EOF'

# Custom Aliases and Tools
alias update='paru -Syu && flatpak update'
alias hyprupdate='~/hyprland-dots/hyprdots/update.sh'
eval "$(starship init bash)"
fastfetch
EOF
)

if $DRY_RUN; then
    echo "[DRY RUN] Would ensure the following lines exist in ~/.bashrc:"
    echo "$bashrc_addition"
else
    while IFS= read -r line; do
        # Skip empty lines to avoid appending unnecessary blanks
        [[ -z "$line" ]] && continue
        if ! grep -Fxq "$line" "$HOME/.bashrc"; then
            echo "$line" >> "$HOME/.bashrc"
        fi
    done <<< "$bashrc_addition"
fi

# Hide unwanted apps from launcher
echo "🔧 Hiding unwanted apps from launcher..."
APPS_FILE="$HOME/hyprland-dots/hyprdots/hide.txt"

if [[ ! -f "$APPS_FILE" ]]; then
    echo "❌ App list file not found: $APPS_FILE"
    exit 1
fi

while IFS= read -r app; do
    [[ -z "$app" || "$app" =~ ^# ]] && continue
    desktop_file="/usr/share/applications/$app.desktop"
    user_desktop_file="$HOME/.local/share/applications/$app.desktop"

    if [[ -f "$desktop_file" ]]; then
        mkdir -p "$HOME/.local/share/applications"
        cp "$desktop_file" "$user_desktop_file"
        if grep -q '^NoDisplay=true' "$user_desktop_file"; then
            echo "$app is already hidden."
        else
            echo "Hiding $app.desktop"
            echo "NoDisplay=true" >> "$user_desktop_file"
        fi
    else
        echo "Could not find $desktop_file"
    fi
done < "$APPS_FILE"

echo "enabling SDDM"
run_cmd "sudo systemctl enable sddm.service"

echo "enabling bluetooth"
run_cmd "sudo systemctl enable bluetooth"
sleep 3
echo "✅ Setup complete. Reboot required"
read -rp "Reboot now? [y/N]: " reboot_now
if [[ "$reboot_now" =~ ^[Yy]$ ]]; then
    run_cmd "reboot"
else
    echo "Reboot skipped. Please reboot manually to apply all changes."
fi
