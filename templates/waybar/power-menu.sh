#!/usr/bin/env bash
set -euo pipefail

if ! command -v fuzzel >/dev/null 2>&1; then
  notify-send "Nirium" "fuzzel is not installed"
  exit 1
fi

choice="$(
  printf '%s\n' \
    "Lock" \
    "Logout" \
    "Suspend" \
    "Reboot" \
    "Shutdown" \
    "Hibernate" \
  | fuzzel --dmenu --prompt "Power > "
)"

case "${choice:-}" in
  "Lock") hyprlock ;;
  "Logout") niri msg action quit ;;
  "Suspend") systemctl suspend ;;
  "Reboot") systemctl reboot ;;
  "Shutdown") systemctl poweroff ;;
  "Hibernate") systemctl hibernate ;;
  *) exit 0 ;;
esac
