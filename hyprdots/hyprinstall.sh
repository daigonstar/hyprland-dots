#!/bin/bash

set -e

# Enable dry run mode with --dry-run
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
  DRY_RUN=true
  echo "🧪 Dry run mode enabled. No changes will be made."
fi

# Helper to run or simulate commands
run_cmd() {
  if $DRY_RUN; then
    echo "[DRY RUN] $*"
  else
    eval "$@"
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
opt=$(read_packages "optional.txt")
nvidia=$(read_packages "nvidia.txt")

# Install git and paru
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

# Optional packages
echo "Optional packages: $opt"
read -rp "Install optional packages? [y/N]: " install_opt
if [[ "$install_opt" =~ ^[Yy]$ ]]; then
  run_cmd "paru -S --noconfirm $opt"
fi

# NVIDIA packages
echo "NVIDIA packages: $nvidia"
read -rp "Install NVIDIA packages? [y/N]: " install_nvidia
if [[ "$install_nvidia" =~ ^[Yy]$ ]]; then
  run_cmd "paru -S --noconfirm $nvidia"
fi

#Install fonts
echo "Please install all fonts to ensure this works"
sleep 2
run_cmd "sudo pacman -S nerd-fonts"

# Copy config directories
dotfiles_dir=~/hyprland-dots/hyprdots/.config
config_targets=(hypr fastfetch rofi waybar swaync)
gitdir=~/hyprland-dots/hyprdots

run_cmd "mkdir -p ~/.config"

for dir in "${config_targets[@]}"; do
  target="$HOME/.config/$dir"
  source="$dotfiles_dir/$dir"

  if [[ -d "$target" ]]; then
    echo "Removing existing config: $target"
    run_cmd "rm -rf \"$target\""
  fi

  if [[ -d "$source" ]]; then
    echo "Copying $source to $target"
    run_cmd "cp -r \"$source\" \"$target\""
  else
    echo "⚠️ Warning: Source directory $source does not exist, skipping..."
  fi
done

# Install cursor
echo "Installing cursor"
run_cmd "sudo cp -r \"$gitdir/icons/Future-cursors\" /usr/share/icons"

# Install wallpapers
read -rp "Install wallpapers? [y/N] " install_wallpaper
if [[ "$install_wallpaper" =~ ^[Yy]$ ]]; then
  run_cmd "mkdir -p ~/Pictures"
  run_cmd "cp -r \"$gitdir/wallpapers\" ~/Pictures"
else
  echo "Skipping wallpaper installation."
fi

# Update .bashrc
echo "🔧 Updating .bashrc with aliases and startup commands..."
bashrc_addition=$(cat <<'EOF'

# Custom Aliases and Tools
alias update='paru -Syu && flatpak update'
eval "$(starship init bash)"
fastfetch
EOF
)

if $DRY_RUN; then
  echo "[DRY RUN] Would append the following to ~/.bashrc:"
  echo "$bashrc_addition"
else
  echo "$bashrc_addition" >> ~/.bashrc
fi
echo "enabling SDDM"
run_cmd "sudo systemctl enable sddm.service"

echo "✅ Setup complete. Reboot required"

sleep 3

run_cmd "reboot"

echo "✅ Setup complete."
