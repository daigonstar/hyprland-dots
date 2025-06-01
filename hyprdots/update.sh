#!/bin/bash

set -e

gitdir=~/hyprland-dots

echo "🔄 Pulling latest changes from git..."
cd "$gitdir"
git pull

dotfiles_dir="$gitdir/.config"
config_targets=(hypr fastfetch rofi waybar swaync wallust)

run_cmd() {
  eval "$@"
}

run_cmd "mkdir -p ~/.config"

# Ask user about backup
read -rp "Do you want to back up your existing config directories before updating them? [y/N]: " backup_configs
if [[ "$backup_configs" =~ ^[Yy]$ ]]; then
  backup_dir="$HOME/.config-backup-update-$(date +%Y%m%d%H%M%S)"
  mkdir -p "$backup_dir"
  echo "Backing up configs to $backup_dir"
fi

for dir in "${config_targets[@]}"; do
  target="$HOME/.config/$dir"
  source="$dotfiles_dir/$dir"
  wsource="$gitdir/wallpaper"

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
  else
    echo "⚠️ Warning: Source directory $source does not exist, skipping..."
  fi
done

# Update starship.toml symlink
if [[ -f "$dotfiles_dir/starship.toml" ]]; then
  echo "Updating starship.toml and wallpapers symlink"
  run_cmd "rm ~.config/starship.toml"
  run_cmd "rm -rf ~/Pictures/wallpapers"
  run_cmd "ln -sfn \"$dotfiles_dir/starship.toml\" ~/.config/starship.toml"
  run_cmd "ln -sfn \"$wsource\" ~/Pictures/wallpapers"
fi

echo "✅ Config update complete."