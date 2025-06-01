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

#debugging

echo "Looking for flatpak.txt in: $(pwd)"
ls -l flatpak.txt

cat "$HOME/hyprland-dots/hyprdots/flatpak.txt"

# Read package lists
req=$(read_packages "required.txt")
nvidia=$(read_packages "nvidia.txt")
flatpak=$(read_packages "$HOME/hyprland-dots/hyprdots/flatpak.txt")

flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# Install flatpak packages
echo "📦 Installing flatpak packages..."
while IFS= read -r pkg; do
  [[ -z "$pkg" ]] && continue
  echo "Would install: $pkg"
done < "$HOME/hyprland-dots/hyprdots/flatpak.txt"
