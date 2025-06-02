#  Hyprland Dotfiles

### This readme requires the installation of a ned font to display correctly

## <font "color=red">I am aware of the volume indicator clipping and am working to fix it</font>

This is the configuration I am currently using for Hyprland
I have tried many dots in the past and I liked them but not ALL of what each one offered so I decided to make my own config
I have borrowed some code from the dots I like (especially JaKoolIt) but have also added my own spin on some things

I have also made an install script that should install everything nicely (I even left in the dry-run command just so you can see exactly what it is doing)

I have added some wallpapers I've collected (will probably add more as I go)

### **Keybinds**

SUPER + Space = Launcher  
SUPER + Q = Quit app  
SUPER + T = Terminal (Ghostty as default)  
SUPER + E = File Manager (Thunar is default)  
SUPER + B = Browser (Zen is default)  
SUPER + A = App Store (Cosmic is default)   
SUPER + N = Refresh waybar  
SUPER SHIFT + N = Launch waybar (used if waybar crashes)

### Default Desktop
![image](/hyprdots/screens/desktop.png)

### Terminal
![image](/hyprdots/screens/term.png)

### **JaKoolIt** Wallpaper selector
![image](/hyprdots/screens/wall.png)

### Applauncher (rofi)
![image](/hyprdots/screens/appl.png)

### Powermenu (JaKoolIt)
![image](/hyprdots/screens/power.png)

### Install:
```bash
git clone https://github.com/daigonstar/hyprland-dots.git
cd hyprland-dots/hyprdots
chmod +x hyprinstall.sh
./hyprinstall.sh
```
#### For my SDDM Greeter I use [SDDM Astronaut Theme](https://github.com/Keyitdev/sddm-astronaut-theme)
Please install that for a better greeter theme
