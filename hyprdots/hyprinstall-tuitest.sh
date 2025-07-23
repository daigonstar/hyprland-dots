#!/bin/bash

set -e

# Define some color variables for better readability
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
RESET="\033[0m"

# Enable dry-run mode with --dry-run
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
  DRY_RUN=true
  echo -e "${YELLOW}🧪 Dry run mode enabled. No changes will be made.${RESET}"
fi

VERBOSE=false
for arg in "$@"; do
  [[ "$arg" == "--verbose" ]] && VERBOSE=true
done

# Helper to run or simulate commands
run_cmd() {
  if $DRY_RUN; then
    echo -e "${YELLOW}[DRY RUN] $*${RESET}"
  else
    if $VERBOSE; then
      echo -e "${YELLOW}[VERBOSE] $*${RESET}"
      bash -c "$@"
    else
      bash -c "$@" > /dev/null 2>&1 &
      pid=$!
      while kill -0 $pid 2>/dev/null; do
        echo -n "."
        sleep 0.7
      done
      wait $pid
      echo -e "${GREEN} done${RESET}"
    fi
  fi
}

# Function to read package list from file
read_packages() {
  local file="$1"
  if [[ -f "$file" ]]; then
    tr '\n' ' ' < "$file"
  else
    echo -e "${RED}❌ Error: $file not found${RESET}" >&2
    exit 1
  fi
}

# Function for TUI input
prompt_user() {
  local message=$1
  local default_answer=$2
  dialog --title "User Prompt" --backtitle "Setup Wizard" --yesno "$message" 7 60
  return $?
}

# Read package lists
req=$(read_packages "required.txt")
nvidia=$(read_packages "nvidia.txt")
flatpak=$(read_packages "$HOME/hyprland-dots/hyprdots/flatpak.txt")

# Install git and paru
echo -e "${YELLOW}📦 Installing git and paru...${RESET}"
run_cmd "sudo pacman -Syu --noconfirm git"

if [[ ! -d "paru" ]]; then
  run_cmd "git clone https://aur.archlinux.org/paru.git"
fi

if [[ -d "paru" ]]; then
  cd paru || exit
  run_cmd "makepkg -si --noconfirm"
  cd ..
fi

echo -e "${GREEN}✅ Paru installed.${RESET}"

# Install required packages
echo -e "${YELLOW}📦 Installing required packages...${RESET}"
for pkg in $req; do
  if pacman -Qq "$pkg" &>/dev/null; then
    echo -e "${GREEN}✅ $pkg is already installed, skipping.${RESET}"
  else
    run_cmd "paru -S --noconfirm $pkg"
  fi
done

# Install flatpak packages
echo -e "${YELLOW}📦 Installing flatpak packages...${RESET}"
while IFS= read -r pkg; do
  [[ -z "$pkg" || "$pkg" =~ ^# || "$pkg" =~ ^// ]] && continue
  flatpak install -y --noninteractive --or-update flathub "$pkg"
done < "$HOME/hyprland-dots/hyprdots/flatpak.txt"

# Ask for NVIDIA installation
prompt_user "Do you want to install NVIDIA packages?" "No"
if [[ $? -eq 0 ]]; then
  echo -e "${YELLOW}NVIDIA packages: $nvidia${RESET}"
  for pkg in $nvidia; do
    if pacman -Qq "$pkg" &>/dev/null; then
      echo -e "${GREEN}✅ $pkg is already installed, skipping.${RESET}"
    else
      run_cmd "paru -S --noconfirm $pkg"
    fi
  done
else
  echo -e "${YELLOW}Skipping NVIDIA packages.${RESET}"
fi

# Dual Boot Option (rEFInd)
prompt_user "Do you want to install rEFInd?" "No"
if [[ $? -eq 0 ]]; then
  echo -e "${YELLOW}Installing rEFInd...${RESET}"
  run_cmd "sudo pacman -S --noconfirm refind"
  run_cmd "sudo refind-install"
  run_cmd "sudo mkdir -p /boot/EFI/refind/themes"
  run_cmd "sudo git clone https://github.com/catppuccin/refind.git /boot/EFI/refind/themes/catppuccin"
  echo 'include themes/catppuccin/mocha.conf' | sudo tee -a /boot/EFI/refind/refind.conf > /dev/null
else
  echo -e "${YELLOW}Skipping rEFInd installation.${RESET}"
fi

# Symlink config directories
dotfiles_dir=~/hyprland-dots/hyprdots/.config
config_targets=(hypr fastfetch rofi waybar swaync wallust ghostty)

# Backup Configuration Option
prompt_user "Do you want to back up your existing config directories before replacing them?" "No"
if [[ $? -eq 0 ]]; then
  backup_dir="$HOME/.config-backup-$(date +%Y%m%d%H%M%S)"
  mkdir -p "$backup_dir"
  echo -e "${YELLOW}Backing up configs to $backup_dir${RESET}"
fi

# Process each directory for symlinks
for dir in "${config_targets[@]}"; do
  target="$HOME/.config/$dir"
  source="$dotfiles_dir/$dir"

  if [[ -d "$target" || -L "$target" ]]; then
    if [[ "$backup_configs" =~ ^[Yy]$ ]]; then
      echo -e "${YELLOW}Backing up $target to $backup_dir/${RESET}"
      run_cmd "cp -r \"$target\" \"$backup_dir/\""
    fi
    echo -e "${YELLOW}Removing existing config: $target${RESET}"
    run_cmd "rm -rf \"$target\""
  fi

  if [[ -d "$source" ]]; then
    echo -e "${YELLOW}Symlinking $source to $target${RESET}"
    run_cmd "ln -sfn \"$source\" \"$target\""
  fi
done

# Enable services
echo -e "${YELLOW}🔧 Enabling scripts...${RESET}"
chmod +x $dotfiles_dir/hypr/scripts/*

# Cursor installation
echo -e "${YELLOW}Installing cursor...${RESET}"
run_cmd "sudo cp -r \"$gitdir/icons/Future-cursors\" /usr/share/icons"

# Bashrc update
echo -e "${YELLOW}🔧 Updating .bashrc...${RESET}"
bashrc_addition=$(cat <<'EOF'

# Custom Aliases and Tools
alias update='paru -Syu && flatpak update'
alias hyprupdate='~/hyprland-dots/hyprdots/update.sh'
eval "$(starship init bash)"
fastfetch
EOF
)

if $DRY_RUN; then
    echo -e "${YELLOW}[DRY RUN] Would ensure the following lines exist in ~/.bashrc:${RESET}"
    echo "$bashrc_addition"
else
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if ! grep -Fxq "$line" "$HOME/.bashrc"; then
            echo "$line" >> "$HOME/.bashrc"
        fi
    done <<< "$bashrc_addition"
fi

# Reboot Option
prompt_user "Reboot now to apply all changes?" "Yes"
if [[ $? -eq 0 ]]; then
    run_cmd "reboot"
else
    echo -e "${YELLOW}Reboot skipped. Please reboot manually.${RESET}"
fi

echo -e "${GREEN}✅ Setup complete. Reboot required.${RESET}"
