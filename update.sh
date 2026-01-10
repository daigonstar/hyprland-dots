#!/usr/bin/env bash
set -euo pipefail

# update.sh
# Safely overwrite this repository with the remote branch state.
# Usage: ./update.sh [remote]
# - Defaults to remote 'origin'.
# Behavior:
# 1. Creates a local backup branch named backup-before-update-<timestamp>.
# 2. Fetches the remote and resets --hard to remote/current-branch.
# 3. Removes untracked files (git clean -fdx).

repo_root="$(cd "$(dirname "$0")" && pwd)"
cd "$repo_root"

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "Error: not a git repository: $repo_root" >&2
  exit 1
fi

remote="${1:-origin}"
branch="$(git rev-parse --abbrev-ref HEAD)"
timestamp="$(date +%Y%m%d-%H%M%S)"
backup_branch="backup-before-update-$timestamp"

echo "Repository: $repo_root"
echo "Current branch: $branch"
echo "Remote: $remote"
echo "Creating backup branch: $backup_branch"
git branch --force "$backup_branch" || git branch "$backup_branch"

echo "Fetching from $remote..."
git fetch --prune "$remote"

if git show-ref --verify --quiet "refs/remotes/$remote/$branch"; then
  echo "Resetting local $branch to $remote/$branch (this will discard local commits not on remote)"
  git reset --hard "$remote/$branch"

  echo "Removing untracked files, including ignored ones (git clean -fdx)"
  git clean -fdx

  echo "Updating submodules (if any)"
  git submodule sync --recursive 2>/dev/null || true
  git submodule update --init --recursive 2>/dev/null || true

  echo "Update complete. Local branch '$branch' now matches '$remote/$branch'."
  echo "Backup of previous HEAD is on branch: $backup_branch"
else
  echo "Error: remote branch '$remote/$branch' not found. Aborting." >&2
  exit 2
fi


  # By default, reapply symlinks and some dotfile tasks so the live system matches the repo.
  # Set SKIP_SYMLINKS=1 to skip this step.
  apply_symlinks() {
    [[ "${SKIP_SYMLINKS:-0}" == "1" ]] && return 0
    echo "Reapplying symlinks and dotfile tasks from repo..."
    REPO_DIR="$repo_root"
    DOTFILES_DIR="$REPO_DIR/.config"

    # Config directories to symlink
    CONFIG_TARGETS=(hypr fastfetch rofi waybar swaync wallust ghostty)
    for dir in "${CONFIG_TARGETS[@]}"; do
      target="$HOME/.config/$dir"
      source="$DOTFILES_DIR/$dir"
      if [[ ! -d "$source" ]]; then
        echo "Source missing: $source (skipping)"
        continue
      fi

      # Special-case 'hypr' to preserve user-local monitor/workspace configs
      if [[ "$dir" == "hypr" ]]; then
        if [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then
          echo "Already symlinked: $target"
          continue
        fi
        if [[ -e "$target" && ! -d "$target" ]]; then
          echo "Backing up existing $target"
          mv "$target" "$target.bak.$timestamp" || true
        fi
        # Ensure target dir exists
        mkdir -p "$target"
        # Sync files from repo to user config but exclude monitors.conf and workspaces.conf
        if command -v rsync >/dev/null 2>&1; then
          rsync -a --delete --exclude='monitors.conf' --exclude='workspaces.conf' "$source/" "$target/"
        else
          # Fallback: use tar to copy excluding the two files
          (cd "$source" && tar cf - --exclude='monitors.conf' --exclude='workspaces.conf' .) | (cd "$target" && tar xpf -)
        fi
        echo "Updated $target from $source (excluded: monitors.conf, workspaces.conf). Local copies (if any) were preserved."
        continue
      fi

      if [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then
        echo "Already symlinked: $target"
        continue
      fi
      [[ -e "$target" ]] && echo "Backing up existing $target" && mv "$target" "$target.bak.$timestamp" || true
      ln -sfn "$source" "$target"
      echo "Symlinked $target -> $source"
    done


    # Starship config
    starship_file="$HOME/.config/starship.toml"
    if [[ -e "$starship_file" ]]; then
      mv "$starship_file" "$starship_file.bak.$timestamp" || true
    fi
    ln -sfn "$DOTFILES_DIR/starship.toml" "$starship_file" || true

    # Wallpapers: copy if present in repo
    wallpaper_src="$REPO_DIR/wallpapers"
    wallpaper_dest="$HOME/Pictures/wallpapers"
    if [[ -d "$wallpaper_src" ]]; then
      [[ -e "$wallpaper_dest" ]] && rm -rf "$wallpaper_dest"
      cp -r "$wallpaper_src" "$wallpaper_dest"
      echo "Copied wallpapers to $wallpaper_dest"
    fi

    # Make key scripts executable (best-effort)
    SCRIPT_FILES=(hypr/scripts/ai.sh hypr/scripts/browser.sh hypr/scripts/gamemode.sh hypr/scripts/pywall.sh hypr/scripts/rainbowb.sh hypr/scripts/refresh.sh hypr/scripts/wallust.sh rofi/powermenu/powermenu.sh rofi/launchers/launcher.sh rofi/wallpaper/wallpaper.sh)
    for s in "${SCRIPT_FILES[@]}"; do
      sp="$DOTFILES_DIR/$s"
      [[ -f "$sp" ]] && chmod +x "$sp" && echo "Chmod +x $sp"
    done

    echo "Symlink and dotfile tasks complete."
  }

  apply_symlinks

  exit 0
