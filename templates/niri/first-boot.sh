#!/usr/bin/env bash
# nirium first-run initialization script
FLAG_FILE="$HOME/.config/nirium-firstboot-done"
[[ -f "$FLAG_FILE" ]] && exit 0

# Wait for Wayland compositor to settle
sleep 2

# ── Set dark GTK theme (adw-gtk3-dark) ───────────────────────────────────────
if command -v gsettings > /dev/null 2>&1; then
  gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'    || true
  gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'    || true
  gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark'     || true
  gsettings set org.gnome.desktop.interface font-name 'Noto Sans 11'      || true
  gsettings set org.gnome.desktop.interface monospace-font-name 'JetBrainsMono Nerd Font 13' || true
  gsettings set org.gnome.desktop.wm.preferences button-layout ''         || true
fi

# ── Generate Monokai-complementary palette from wallpaper (matugen) ──────────
WALLPAPER="/usr/share/backgrounds/nirium-dark.png"
if command -v matugen > /dev/null 2>&1 && [[ -f "$WALLPAPER" ]]; then
  matugen image "$WALLPAPER" --mode dark 2>/dev/null || true
fi

# ── Welcome notification ──────────────────────────────────────────────────────
if command -v notify-send > /dev/null 2>&1; then
  notify-send "Welcome to Nirium" \
    "Mod+Space: launcher  •  Mod+N: notifications  •  Super+Alt+L: lock" \
    --icon=system-help
fi

# ── Removable drives shortcut (macOS-like) ───────────────────────────────────
# udiskie mounts removable drives at /run/media/$USER; expose a stable shortcut.
if [[ ! -e "$HOME/Volumes" ]]; then
  ln -s "/run/media/$USER" "$HOME/Volumes" || true
fi

touch "$FLAG_FILE"
