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
  install -d "/mnt${user_home}/.config/niri"
  install -d "/mnt${user_home}/Pictures/Screenshots"
  install -d /mnt/usr/share/backgrounds

  log "Applying Nirium declarative defaults"
  
  # Install nirium manager
  install -m 755 "$SCRIPT_DIR/../nirium.sh" /mnt/usr/bin/nirium

  # Create default configuration.toml
  install -d /mnt/etc/nirium
  cat > /mnt/etc/nirium/configuration.toml <<'EOF'
[system]
channel = "main"

[components]
niri = true
waybar = true
fuzzel = true
swaync = true
hyprlock = true
hypridle = true
kitty = true
theme = true
wlogout = true
starship = true
EOF

  # Bootstrap declarative configurations to /etc/xdg
  # Do NOT use /tmp — arch-chroot mounts a fresh tmpfs over it, wiping the payload.
  mkdir -p /mnt/root/nirium-bootstrap
  cp -a "$SCRIPT_DIR/.." /mnt/root/nirium-bootstrap/v2
  chmod +x /mnt/usr/bin/nirium
  arch-chroot /mnt bash -c "nirium bootstrap /root/nirium-bootstrap/v2"
  rm -rf /mnt/root/nirium-bootstrap

  # Install non-declarative home user files
  if [[ ! -f "/mnt${user_home}/.config/niri/first-boot.sh" ]]; then
    install -m 755 "$SCRIPT_DIR/../templates/niri/first-boot.sh" "/mnt${user_home}/.config/niri/first-boot.sh"
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
  echo "Next: swapoff -a && umount -R /mnt && reboot"
  end_stage_logging "2-desktop"
}

main "$@"
