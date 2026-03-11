#!/usr/bin/env bash
set -Eeuo pipefail

mode="${1:-area}"
screenshots_dir="${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots"
timestamp="$(date '+%Y-%m-%d %H-%M-%S')"
target_file="$screenshots_dir/Screenshot from ${timestamp}.png"

mkdir -p "$screenshots_dir"

notify_saved() {
  if command -v notify-send >/dev/null 2>&1; then
    notify-send "Screenshot saved" "$1" -u low >/dev/null 2>&1 || true
  fi
}

capture_and_copy() {
  grim "$@" - | tee "$target_file" | wl-copy
  notify_saved "${target_file} (copied to clipboard)"
}

case "$mode" in
  area)
    geometry="$(slurp)" || exit 0
    capture_and_copy -g "$geometry"
    ;;
  output)
    output_name="$(slurp -o -f '%o')" || exit 0
    capture_and_copy -o "$output_name"
    ;;
  window)
    niri msg action screenshot-window
    ;;
  screen)
    niri msg action screenshot-screen
    ;;
  *)
    echo "Usage: $0 [area|output|window|screen]" >&2
    exit 1
    ;;
esac
