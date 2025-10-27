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
      local dot_state=0
      local dots_output=("   " ".  " ".. " "...")
      local max_dot_states=${#dots_output[@]}

      bash -c "$@" > /dev/null 2>&1 &
      pid=$!
      # Loop while the process is still running
      while kill -0 $pid 2>/dev/null; do
        # Print the current dot state. \r moves the cursor to the beginning of the line
        printf "\r%s" "${dots_output[$dot_state]}"
        dot_state=$(( (dot_state + 1) % max_dot_states ))
        sleep 0.7 #
      done
      wait $pid
      local cmd_exit_status=$? # Get the exit status of the command that finished

      # Clear the line where the dots were animating by printing spaces and carriage return
      printf "\\r   \\r"
      if [[ $cmd_exit_status -eq 0 ]]; then
        echo " done" # Print " done" on a new line for success
      else
        echo " failed (exit code: $cmd_exit_status)" # Print failure message
      fi
      return $cmd_exit_status # Return the actual exit status of the command
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
req=$(read_packages "$(dirname "$0")/required.txt")
nvidia=$(read_packages "$(dirname "$0")/nvidia.txt")
flatpak=$(read_packages "$(dirname "$0")/flatpak.txt") # Corrected path
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
for pkg in $req; do
  if pacman -Qq "$pkg" &>/dev/null; then
    echo "✅ Package '$pkg' is already installed, skipping."
  else
    run_cmd "paru -S --noconfirm $pkg"
  fi
done

# Install flatpak packages
echo "📦 Installing flatpak packages..."
while IFS= read -r pkg; do
  [[ -z "$pkg" || "$pkg" =~ ^# || "$pkg" =~ ^// ]] && continue
  if flatpak list --app | grep -qw "$pkg"; then
    echo "✅ Flatpak '$pkg' is already installed, skipping."
  else
    run_cmd "flatpak install -y --noninteractive --or-update flathub \"$pkg\""
  fi
done < "$(dirname "$0")/flatpak.txt" # Corrected path

# NVIDIA packages
read -rp "Do you want to install NVIDIA packages? [y/N]: " install_nvidia
if [[ "$install_nvidia" =~ ^[Yy]$ ]]; then
  echo "📦 Installing NVIDIA packages..."
  for pkg in $nvidia; do
    if pacman -Qq "$pkg" &>/dev/null; then
      echo "✅ NVIDIA package $pkg is already installed, skipping."
    else
      run_cmd "paru -S --noconfirm $pkg"
    fi
  done
else
  echo "Skipping NVIDIA packages installation."
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

# Symlink config directories
dotfiles_dir=~/hyprland-dots/hyprdots/.config
config_targets=(hypr fastfetch rofi waybar swaync wallust ghostty)
gitdir=~/hyprland-dots/hyprdots

#Create home directories

echo "📂 Creating essential home directories..."
run_cmd "mkdir -p ~/Pictures"
run_cmd "mkdir -p ~/Videos"
run_cmd "mkdir -p ~/Documents"

# Ask user about backup
read -rp "Do you want to back up your existing config directories before replacing them? [y/N]: " backup_configs
if [[ "$backup_configs" =~ ^[Yy]$ ]]; then
  backup_dir="$HOME/.config-backup-$(date +%Y%m%d%H%M%S)"
  mkdir -p "$backup_dir"
  echo "Backing up configs to $backup_dir"
fi

echo "🔗 Symlinking config directories..."
for dir in "${config_targets[@]}"; do
  target="$HOME/.config/$dir"
  source="$dotfiles_dir/$dir"

  echo "Processing config for '$dir'..."
  if [[ -d "$target" || -L "$target" ]]; then
    if [[ "$backup_configs" =~ ^[Yy]$ ]]; then
      echo "Backing up existing '$target' to '$backup_dir/'"
      run_cmd "cp -r \"$target\" \"$backup_dir/\""
    fi
    echo "Removing existing config directory: '$target'"
    run_cmd "rm -rf \"$target\""
  fi

  if [[ -d "$source" ]]; then
    echo "Symlinking '$source' to '$target'"
    run_cmd "ln -sfn \"$source\" \"$target\""
  else
    echo "⚠️ Warning: Source directory '$source' not found, skipping symlink for '$dir'."
  fi
done

echo "🔗 Symlinking starship.toml..."
if [[ -e "$HOME/.config/starship.toml" || -L "$HOME/.config/starship.toml" ]]; then
  echo "Removing existing starship.toml"
  run_cmd "rm \"$HOME/.config/starship.toml\""
fi
run_cmd "ln -sfn \"$dotfiles_dir/starship.toml\" \"$HOME/.config/starship.toml\""

# Handle wallpapers separately
echo "🖼️ Copying wallpapers..."
if [[ -e "$HOME/Pictures/wallpapers" || -L "$HOME/.Pictures/wallpapers" ]]; then
  echo "Removing existing wallpapers directory."
  run_cmd "rm -rf \"$HOME/Pictures/wallpapers\""
fi
if [[ -d "$gitdir/wallpapers" ]]; then
  echo -n "Copying wallpapers to '$HOME/Pictures/wallpapers'" # Initial message, 'run_cmd' will append dots/done/failed
  if run_cmd "cp -r \"$gitdir/wallpapers\" \"$HOME/Pictures/wallpapers\""; then
    echo "✅ Wallpapers copied successfully."
  else
    echo "❌ Failed to copy wallpapers."
  fi
else
  echo "⚠️ Warning: Wallpapers directory at '$gitdir/wallpapers' was not found, skipping copy."
fi

# Enable scripts
echo "🔧 Setting execute permissions for scripts..."
script_files=(
  "hypr/scripts/ai.sh"
  "hypr/scripts/browser.sh"
  "hypr/scripts/gamemode.sh"
  "hypr/scripts/pywall.sh"
  "hypr/scripts/rainbowb.sh"
  "hypr/scripts/refresh.sh"
  "hypr/scripts/wallust.sh"
  "rofi/powermenu/powermenu.sh"
  "rofi/launchers/launcher.sh"
  "rofi/wallpaper/wallpaper.sh"
)

for script in "${script_files[@]}"; do
  script_path="$dotfiles_dir/$script"
  if [[ -f "$script_path" ]]; then
    echo "Setting execute permission for '$script'..."
    run_cmd "chmod +x \"$script_path\""
  else
    echo "⚠️ Warning: Script '$script_path' not found, skipping chmod."
  fi
done

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

echo "enabling SDDM"
run_cmd "sudo systemctl enable sddm.service"

echo "🎨 Installing SDDM theme..."
run_cmd "sudo cp -R $gitdir/SDDM/sugar-dark /usr/share/sddm/themes"
run_cmd "sudo mkdir -p /etc/sddm.conf.d" # Ensure directory exists
run_cmd "sudo cp $gitdir/SDDM/sddm.conf /etc/sddm.conf.d/sddm.conf"

echo "enabling coolercontrol service"
run_cmd "sudo systemctl enable --now coolercontrold"

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
