#!/usr/bin/env bash

if [[ -z ${BASH_VERSION:-} ]]; then
  exec bash "$0" "$@"
fi

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

usage() {
  cat <<'USAGE'
Stage 2: desktop polish + GPU + DMS baseline

Usage:
  sudo bash 2-packages.sh [options]

Options:
  --user osman       Target user (defaults to saved stage 1 user)
  -h, --help
USAGE
}

main() {
  local username=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --user)
        username="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
  done

  begin_stage_logging "2-desktop"
  trap 'on_stage_error "2-desktop" "$LINENO" "$BASH_COMMAND"' ERR

  require_root
  ensure_uefi
  require_cmds arch-chroot findmnt lsblk swapon mount genfstab install cp awk cut sed

  log "Stage 2: desktop polish + GPU tuning"
  log "DMS baseline is enabled"

  ensure_target_mounted
  read_target_context

  username="${username:-$(read_state_value USERNAME)}"
  username="${username:-${SUDO_USER:-}}"
  username="${username:-archuser}"
  username="$(prompt_default "Main username" "$username")"

  local extra_kernel_cmdline=""
  extra_kernel_cmdline="$(read_state_value EXTRA_KERNEL_CMDLINE)"

  local desktop_packages_file="$SCRIPT_DIR/../packages/desktop.pacman"
  local PKG_LIST=()
  read_package_file "$desktop_packages_file"

  log "Installing desktop utility packages"
  arch-chroot /mnt pacman -S --noconfirm --needed "${PKG_LIST[@]}"


  # Copy the chroot script into /root/ inside the target.
  # Do NOT use /tmp — arch-chroot mounts a fresh tmpfs over it, wiping the file.
  install -m 700 "$SCRIPT_DIR/2-desktop-chroot.sh" /mnt/root/nirium-2-desktop-chroot.sh

  arch-chroot /mnt env \
    USERNAME="$username" \
    ROOT_PART="$ROOT_PART" \
    SWAP_PART="$SWAP_PART" \
    EXTRA_KERNEL_CMDLINE="$extra_kernel_cmdline" \
    /bin/bash /root/nirium-2-desktop-chroot.sh

  rm -f /mnt/root/nirium-2-desktop-chroot.sh


  local user_home=""
  local user_uid=""
  local user_gid=""

  user_home="$(arch-chroot /mnt getent passwd "$username" | cut -d: -f6)"
  [[ -n $user_home ]] || die "Unable to resolve home directory for $username"

  user_uid="$(arch-chroot /mnt id -u "$username")"
  user_gid="$(arch-chroot /mnt id -g "$username")"

  log "Applying user configs for $username"
  install -d "/mnt${user_home}/.config/kitty"    "/mnt${user_home}/.config/niri"
  install -d "/mnt${user_home}/.config/waybar"   "/mnt${user_home}/.config/swaync"
  install -d "/mnt${user_home}/.config/fuzzel"   "/mnt${user_home}/.config/hypr"
  install -d "/mnt${user_home}/Pictures/Screenshots"
  install -d /mnt/usr/share/backgrounds

  if [[ -d "$SCRIPT_DIR/../templates/theme" ]]; then
    cp -r "$SCRIPT_DIR/../templates/theme" "/mnt${user_home}/.config/"
  fi
  if [[ -d "$SCRIPT_DIR/../templates/wlogout" ]]; then
    cp -r "$SCRIPT_DIR/../templates/wlogout" "/mnt${user_home}/.config/"
  fi

  if [[ ! -f "/mnt${user_home}/.config/kitty/current-theme.conf" ]]; then
    cp "$SCRIPT_DIR/../templates/kitty/current-theme.conf" "/mnt${user_home}/.config/kitty/current-theme.conf"
  fi
  if [[ ! -f "/mnt${user_home}/.config/kitty/kitty.conf" ]]; then
    cp "$SCRIPT_DIR/../templates/kitty/kitty.conf" "/mnt${user_home}/.config/kitty/kitty.conf"
  fi
  if [[ ! -f "/mnt${user_home}/.config/niri/config.kdl" ]]; then
    cp "$SCRIPT_DIR/../templates/niri/config.kdl"        "/mnt${user_home}/.config/niri/config.kdl"
    cp "$SCRIPT_DIR/../templates/niri/startup.kdl"       "/mnt${user_home}/.config/niri/startup.kdl"
    cp "$SCRIPT_DIR/../templates/niri/input.kdl"         "/mnt${user_home}/.config/niri/input.kdl"
    cp "$SCRIPT_DIR/../templates/niri/binds.kdl"         "/mnt${user_home}/.config/niri/binds.kdl"
    cp "$SCRIPT_DIR/../templates/niri/window-rules.kdl"  "/mnt${user_home}/.config/niri/window-rules.kdl"
  fi
  if [[ ! -f "/mnt${user_home}/.config/niri/first-boot.sh" ]]; then
    install -m 755 "$SCRIPT_DIR/../templates/niri/first-boot.sh" "/mnt${user_home}/.config/niri/first-boot.sh"
  fi
  if [[ ! -f "/mnt${user_home}/.config/waybar/config.jsonc" ]]; then
    cp "$SCRIPT_DIR/../templates/waybar/config.jsonc" "/mnt${user_home}/.config/waybar/config.jsonc"
    cp "$SCRIPT_DIR/../templates/waybar/style.css"    "/mnt${user_home}/.config/waybar/style.css"
  fi
  if [[ ! -f "/mnt${user_home}/.config/swaync/config.json" ]]; then
    cp "$SCRIPT_DIR/../templates/swaync/config.json" "/mnt${user_home}/.config/swaync/config.json"
    cp "$SCRIPT_DIR/../templates/swaync/style.css"   "/mnt${user_home}/.config/swaync/style.css"
  fi
  if [[ ! -f "/mnt${user_home}/.config/fuzzel/fuzzel.ini" ]]; then
    cp "$SCRIPT_DIR/../templates/fuzzel/fuzzel.ini" "/mnt${user_home}/.config/fuzzel/fuzzel.ini"
  fi
  if [[ ! -f "/mnt${user_home}/.config/hypr/hyprlock.conf" ]]; then
    cp "$SCRIPT_DIR/../templates/hypr/hyprlock.conf" "/mnt${user_home}/.config/hypr/hyprlock.conf"
    cp "$SCRIPT_DIR/../templates/hypr/hypridle.conf" "/mnt${user_home}/.config/hypr/hypridle.conf"
  fi
  if [[ ! -f "/mnt${user_home}/.zshrc" ]]; then
    cp "$SCRIPT_DIR/../templates/zsh/.zshrc" "/mnt${user_home}/.zshrc"
  fi

  if [[ ! -f "/mnt${user_home}/.config/mimeapps.list" ]]; then
    cat > "/mnt${user_home}/.config/mimeapps.list" <<'MIMEAPPS'
[Default Applications]
image/png=imv.desktop
image/jpeg=imv.desktop
x-scheme-handler/http=firefox.desktop
x-scheme-handler/https=firefox.desktop
video/mp4=mpv.desktop
video/x-matroska=mpv.desktop
text/plain=nvim.desktop
MIMEAPPS
  fi

  chown -R "$user_uid:$user_gid" "/mnt${user_home}/.config"
  chown -R "$user_uid:$user_gid" "/mnt${user_home}/.local"

  save_state_value USERNAME "$username"

  echo
  log "Stage 2 complete"
  echo "Target remains mounted at /mnt"
  echo "Next: umount -R /mnt && reboot"
  end_stage_logging "2-desktop"
}

main "$@"
