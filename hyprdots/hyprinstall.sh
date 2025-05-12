#!/bin/bash


#test
# Application variables
req="hyprland rofi-wayland waybar nwg-displays nwg-look hyprshot swaync libnotify hyprlock hypridle hyprpaper ttf-cascadia-code-nerd pavucontrol playerctl xorg-xwayland wayland-protocols hyprpolkitagent xdg-desktop-portal-gtk xdg-desktop-portal-hyprland gnome-themes-extra ffmpegthumbnailer tumbler"
opt="ghostty flatpak buah firefox thunar stow starship plymouth"
nvidia="nvidia-dkms linux-headers nvidia-utils libva-nvidia-driver"

# Install git and paru
sudo pacman -Syu --noconfirm git

git clone https://aur.archlinux.org/paru.git
cd paru || exit
makepkg -si --noconfirm

echo "Paru now installed."

# Install required packages
echo "Now installing required packages"
paru -S --noconfirm $req


echo "Would you like the optional packages? ($opt)"
read -rp "Install optional packages? [y/N]: " install_opt
if [[ "$install_opt" =~ ^[Yy]$ ]]; then
  paru -S --noconfirm $opt
fi

echo "Are you using NVIDIA graphics?"
read -rp "Install NVIDIA packages? [y/N]: " install_nvidia
if [[ "$install_nvidia" =~ ^[Yy]$ ]]; then
  paru -S --noconfirm $nvidia
fi