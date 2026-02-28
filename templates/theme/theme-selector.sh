#!/usr/bin/env bash
# Theme and Background selector using fuzzel

BG_DIR="$HOME/.config/theme/bg"
mkdir -p "$BG_DIR"

# Ensure there's a symlink for the current background if it doesn't exist
if [[ ! -f "$BG_DIR/current" ]]; then
    ln -sf "$BG_DIR/bg-1.jpg" "$BG_DIR/current"
fi

# Select a new background
SELECTED=$(ls -1 "$BG_DIR" | grep -v '^current$' | fuzzel --dmenu -p "Select Background: " -l 10)
if [[ -n "$SELECTED" ]]; then
    IMAGE_PATH="$BG_DIR/$SELECTED"
    
    # Save the current background for next boot
    ln -sf "$IMAGE_PATH" "$BG_DIR/current"
    
    # Restart swaybg
    pkill swaybg
    swaybg -i "$BG_DIR/current" -m fill &
fi
