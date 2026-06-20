# Merge 3.1 - Conflict Resolution Guide

## Current State
- **PR**: #23 (Merge 3.1)
- **Base Branch**: `dev`
- **Head Branch**: `main`
- **Status**: ❌ Unmergeable - "dirty" state due to conflicts

## Key Changes from main → dev (97 files, 4,029 additions, 676 deletions)

### Major Additions:
1. **Hypr-Dock Configuration** - New dock system with themes
2. **Swaync Integration** - SwayNC notification daemon setup
3. **Settings TUI** - Python-based settings editor for keybinds/autostart
4. **Multi-Monitor Support** - Monitor and workspace configurations
5. **Enhanced Wallpaper System** - Improved wallust integration with awww-daemon
6. **New Vesktop Theme** - ClearVision Discord theme
7. **Extended Configuration Scripts** - New scripts for system management

### Modified Files (Notable):
- `.config/hypr/keybinds.conf` - Reorganized with category headers
- `.config/hypr/window.conf` - Modern window rule syntax (v0.53+)
- `.config/hypr/autostart.conf` - Updated daemon configuration
- `.config/rofi/colors.rasi` - Color updates from wallust
- `.config/waybar/config` - New modules and settings panel
- `hyprinstall.sh` - Installation script improvements
- Wallpapers - Several new anime/sci-fi wallpapers added

### Deletions:
- Some old wallpapers
- Deprecated configuration files

## How to Resolve

Since main has all the changes and you want to bring them to dev, the strategy is:
1. **Use main's version for most files** (the newer configuration)
2. **Test compatibility** with dev's base setup
3. **Manual conflict resolution** for files with actual conflicts

## Conflict Resolution Strategy

Run this sequence:

```bash
# Ensure you're on the PR branch
git fetch origin

# Check conflict markers
git diff --name-only --diff-filter=U

# For each conflicted file, you typically want main's version:
git checkout --theirs <conflicted-file>

# Then add the resolved files
git add .

# Complete the merge
git commit -m "Resolve merge conflicts: accept main's changes for v3.1 updates"

# Push to update the PR
git push origin HEAD:refs/heads/main
```

## Potential Issues to Watch

1. **File Permissions** - Scripts may need chmod +x
2. **Config Syntax** - Hyprland syntax changed between versions
3. **Symlink References** - Wallust/theme symlinks need valid paths
4. **Path Assumptions** - Scripts assume /home/robb - verify for your system

## Recommended Next Steps

1. After merging, test the configuration
2. Run `hyprinstall.sh` to ensure all dependencies
3. Check `.config/hypr/userconf.conf` - verify input settings
4. Test wallpaper switching and color generation
5. Verify all scripts have execute permissions
