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
    run_cmd "rm ~/.config/starship.toml"
    run_cmd "ln -s $dotfiles_dir/starship.toml ~/.config/starship.toml"
    run_cmd "rm -rf ~/Pictures/wallpapers"
    run_cmd "ln -sfn $gitdir/wallpapers ~/Pictures/wallpapers"
    run_cmd "rm ~/.bashrc"
    run_cmd "ln -s $gitdir/bash/.bashrc ~/.bashrc"
  else
    echo "⚠️ Warning: Source directory $source does not exist, skipping..."
  fi
done

#chmod +x ~/.config/hypr/scripts/ai.sh
#chmod +x ~/.config/hypr/scripts/browser.sh
#chmod +x ~/.config/hypr/scripts/gamemode.sh
#chmod +x ~/.config/hypr/scripts/pywall.sh
#chmod +x ~/.config/hypr/scripts/rainbowb.sh
#chmod +x ~/.config/hypr/scripts/refresh.sh
#chmod +x ~/.config/hypr/scripts/wallust.sh
#chmod +x ~/.config/rofi/powermenu/powermenu.sh
#chmod +x ~/.config/rofi/launcher/launcher.sh
#chmod +x ~/.config/rofi/wallpaper/wallpaper.sh

# Install cursor
echo "Installing cursor"
run_cmd "sudo cp -r "$gitdir/icons/Future-cursors" /usr/share/icons"

flatpak --user override --filesystem=/home/$USER/.icons/:ro
flatpak --user override --filesystem=/usr/share/icons/:ro 


# Update .bashrc
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
