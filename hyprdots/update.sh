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

dotfiles_dir=~/hyprland-dots/hyprdots/.config
config_targets=(hypr fastfetch rofi waybar swaync wallust)
gitdir=~/hyprland-dots

echo "🔄 Pulling latest changes from git..."
cd "$gitdir"
git pull

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
    fi
done

echo "✅ Config update complete."