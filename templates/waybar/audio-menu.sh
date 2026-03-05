#!/usr/bin/env bash
set -euo pipefail

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

notify_missing() {
  if need_cmd notify-send; then
    notify-send "Nirium Audio" "$1"
  fi
}

if ! need_cmd kitty; then
  notify_missing "kitty is not installed"
  exit 1
fi

if ! need_cmd pulsemixer; then
  notify_missing "pulsemixer is not installed"
  exit 1
fi

if ! need_cmd wpctl; then
  notify_missing "wpctl is not installed"
  exit 1
fi

default_output_name() {
  wpctl status 2>/dev/null | awk '
    /^[[:space:]]*Sinks:/ {in_sinks=1; next}
    in_sinks && /^[[:space:]]*[A-Za-z].*:/ {in_sinks=0}
    /\*/ {
      line=$0
      sub(/^[^0-9*]*\*[[:space:]]*/, "", line)
      sub(/^[0-9]+\.[[:space:]]*/, "", line)
      sub(/[[:space:]]*\[vol:.*$/, "", line)
      print line
      exit
    }
  '
}

current_output="$(default_output_name)"
current_output="${current_output:-Unknown}"

# No GTK UI: open pulsemixer TUI in kitty with current output name in title.
exec kitty --class pulsemixer --title "Audio: ${current_output}" -e pulsemixer
