# nirium

A keyboard-centric Arch Linux desktop environment built on **Wayland** and **Niri**.

> [!CAUTION]
> **Warning: Unstable Software**
> Nirium is a toy project but I use daily so use with caution.

## 📖 Motivation

Nirium is a fork of **Omarchy** and aims to copy its zero-friction experience to the Niri window manager.

While doing this; I cropped some parts that I dont like with Omarchy. The goal is to remove most of the opinionated 3rd party commercial apps from Omarchy, change Hyperland with Niri and provide detached configs so no configs is updated/overwritten when updating distro. No omarchy-xxx dependency. So updating is user's responsibility.

---

## At a Glance

| Component | Tool |
| :--- | :--- |
| **Window Manager** | Niri (scrollable tiling, Wayland-native) |
| **Status Bar** | Waybar  |
| **App Launcher** | Fuzzel |
| **Notifications** | SwayNC (sliding panel, `Mod+N`) |
| **Wallpaper** | swaybg |
| **Terminal & Shell** | `kitty` + `zsh` (Starship, autosuggestions, syntax highlighting) |
| **File Manager** | `yazi` (terminal) |
| **Networking** | NetworkManager + `impala` (TUI) |
| **Bluetooth** | `bluetui` (terminal UI) |
| **Audio** | pipewire + wireplumber + `pamixer` |
| **Image Viewer** | `imv` |
| **Clipboard** | `cliphist` + `wl-clipboard` |
| **Auto-theming** | `matugen` (generates palette from wallpaper on first boot) |
| **Bootloader** | `limine` |
| **Filesystem** | `btrfs` with `snapper` auto-snapshots |

---

## Installation

### 1. Preparation

1. Download the latest Arch Linux ISO and flash it to a USB drive.
2. Boot from the USB. Ensure you are connected to the internet (`iwctl` for WiFi).
3. Clone this repository into the live environment:

```bash
git clone https://github.com/osmanorhan/nirium.git
cd nirium
```

### 2. Run the Installer

```bash
sudo bash install.sh all
```
The installer has some stages, "all" runs all stages. You can also run stages individually if you experience any issues.

The installer will prompt you for:
- Target disk (e.g., `/dev/nvme0n1`)
- Hostname, username, and user shell (`/bin/zsh` default)
- Keyboard layout, timezone, and locale
- Root and user passwords

#### Advanced / Non-Interactive Install

```bash
# Only run the base partitioning and pacstrap stage:
sudo bash install.sh packaging --disk /dev/sda --swap-gib 16

# Only run system configuration (chroot stage 1):
sudo bash install.sh config --hostname snow --user osman

# Install desktop environment and configure dotfiles (chroot stage 2):
sudo bash install.sh desktop
```

### 3. First Boot

After the installer finishes, type `reboot`.
Nirium is configured with **autologin** enabled by default. You will boot directly into the Niri desktop with Waybar visible at the top.

On first login, `matugen` automatically generates a color palette from the wallpaper and applies it across the desktop.

---

## ⌨️ Quick Reference: Keybindings

The `Mod` key is your **Super/Windows** key.

### Launchers & Apps
| Key | Action |
| :--- | :--- |
| `Mod + Space` | App launcher (Fuzzel) |
| `Mod + Return` | Terminal (`kitty`) |
| `Mod + Shift + Return` | File manager (`yazi`) |
| `Mod + B` | Browser (Firefox) |
| `Mod + V` | Clipboard history |

### Panels & System
| Key | Action |
| :--- | :--- |
| `Mod + N` | Notification center / quick panel |
| `Mod + Escape` | System monitor (`btop`) |
| `Super + Alt + L` | Lock screen |
| `Mod + Alt + P` | Poweroff |
| `Mod + Alt + R` | Reboot |
| `Mod + Alt + S` | Suspend |
| `Mod + Shift + E` | Power menu |

### Windows & Layout
| Key | Action |
| :--- | :--- |
| `Mod + Q` | Close window |
| `Mod + F` | Toggle fullscreen |
| `Mod + Shift + F` | Toggle floating |
| `Mod + C` | Center floating window |
| `Mod + H/J/K/L` | Move focus (vim-style) |
| `Mod + Shift + H/J/K/L` | Move window |
| `Mod + - / =` | Resize column |
| `Mod + Shift + S / Print` | Screenshot |

### Workspaces
| Key | Action |
| :--- | :--- |
| `Mod + 1–9` | Go to workspace |
| `Mod + Shift + 1–9` | Move window to workspace |
| `Mod + Tab` | Previous workspace |
| `Mod + Ctrl + H/L` | Cycle workspaces |

### Media Keys
Volume and brightness keys are handled natively via `wpctl` and `brightnessctl`.

---

## ⚙️ Configuration & Customization

Nirium uses a declarative, Nix-like architecture for Wayland applications. Rather than copying configurations into your home directory, Nirium installs system-wide immutable defaults to `/etc/xdg/` managed by `/etc/nirium/configuration.toml`.

**Your `~/.config` is strictly yours.** Nirium seeds missing component paths in `~/.config` as defaults (symlinks or writable copies when needed). If you create a real customized configuration in `~/.config`, it immediately and completely overrides the Nirium default, granting you full control.

### The `nirium` CLI

Nirium features a rolling updater that preserves existing `~/.config` overrides and only creates missing default symlinks.

- **Update Defaults**: `sudo nirium update`
  Fetches the latest `configuration.toml` components from upstream, synchronizes required system packages via `pacman`, updates the `nirium` tool itself, generates an immutable profile in `/opt/nirium/generations/latest/`, safely repoints `/etc/xdg/` symlinks, and seeds missing user defaults in `~/.config/`.

- **Rollback Updates**: `sudo nirium rollback`
  If an update breaks a component, this instantly swaps `/etc/xdg/` back to the `previous` generation.

- **Detach and Customize**: `sudo nirium detach <component>`
  *(Example: `nirium detach waybar`)*
  Copies the current Nirium default configuration directly into your `~/.config/waybar/` directory. Since user configs override system defaults, you are now completely detached from the rolling updates for this specific component and can edit it freely knowing it is safe.

- **List Generations**: `nirium list`
  Shows current and previous system generations.

- **Verify and Repair**: `sudo nirium doctor`
  Verifies the system state against your configuration and automatically repairs any broken symlinks in `/etc/xdg/` or missing initial component files in `~/.config/`. Useful if data goes missing after a fresh install.

### Theming
Nirium ships a **Monokai** palette applied across Waybar and SwayNC. On first boot, a complementary Monokai palette is generated from the wallpaper via `matugen`. To regenerate colors from a different wallpaper manually:

```bash
matugen image ~/path/to/wallpaper.png --mode dark
```

### Networking & Bluetooth
- **Waybar** shows your Wi-Fi SSID and Bluetooth status.
- Click the network icon on Waybar to open **impala** for Wi-Fi management.
- Click the Bluetooth icon on Waybar to open **bluetui** for Bluetooth pairing.

### Removing Autologin
1. Open `/etc/sddm.conf.d/10-nirium.conf`
2. Delete the `[Autologin]` section entirely.
3. Reboot.
