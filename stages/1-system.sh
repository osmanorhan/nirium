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
Stage 1: system configuration (locale/users/limine/services)

Usage:
  sudo bash 1-settings.sh [options]

Options:
  --keymap us
  --timezone Europe/Istanbul
  --locale en_US.UTF-8
  --hostname archniri
  --user osman
  --extra-cmdline "..."
  -h, --help
USAGE
}

main() {
  local keymap=""
  local timezone=""
  local locale=""
  local hostname=""
  local username=""
  local extra_kernel_cmdline=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --keymap)
        keymap="$2"
        shift 2
        ;;
      --timezone)
        timezone="$2"
        shift 2
        ;;
      --locale)
        locale="$2"
        shift 2
        ;;
      --hostname)
        hostname="$2"
        shift 2
        ;;
      --user)
        username="$2"
        shift 2
        ;;
      --extra-cmdline)
        extra_kernel_cmdline="$2"
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

  begin_stage_logging "1-system"
  trap 'on_stage_error "1-system" "$LINENO" "$BASH_COMMAND"' ERR

  require_root
  ensure_uefi
  require_cmds arch-chroot timedatectl findmnt lsblk swapon mount genfstab

  log "Stage 1: system settings + bootloader + services"
  timedatectl set-ntp true

  ensure_target_mounted
  read_target_context

  keymap="${keymap:-$(read_state_value KEYMAP)}"
  timezone="${timezone:-$(read_state_value TIMEZONE)}"
  locale="${locale:-$(read_state_value LOCALE)}"
  hostname="${hostname:-$(read_state_value HOSTNAME)}"
  username="${username:-$(read_state_value USERNAME)}"
  username="${username:-${SUDO_USER:-}}"
  extra_kernel_cmdline="${extra_kernel_cmdline:-$(read_state_value EXTRA_KERNEL_CMDLINE)}"

  keymap="${keymap:-us}"
  timezone="${timezone:-Europe/Istanbul}"
  locale="${locale:-en_US.UTF-8}"
  hostname="${hostname:-archniri}"
  username="${username:-archuser}"

  keymap="$(prompt_default "Keyboard layout" "$keymap")"
  timezone="$(prompt_default "Timezone (e.g. Europe/Istanbul)" "$timezone")"
  locale="$(prompt_default "Locale" "$locale")"
  hostname="$(prompt_default "Hostname" "$hostname")"
  username="$(prompt_default "Main username" "$username")"
  extra_kernel_cmdline="$(prompt_default "Extra kernel cmdline (empty for none)" "$extra_kernel_cmdline")"
  username_shell="$(prompt_default "User shell (e.g. /bin/zsh, /bin/bash, /bin/fish)" "/bin/zsh")"

  [[ -e "/usr/share/zoneinfo/$timezone" ]] || die "Invalid timezone: $timezone (not found in /usr/share/zoneinfo)"

  local user_password=""
  local root_password=""
  user_password="$(prompt_secret_confirm "User password ($username)")"
  root_password="$user_password"

  save_state_value KEYMAP "$keymap"
  save_state_value TIMEZONE "$timezone"
  save_state_value LOCALE "$locale"
  save_state_value HOSTNAME "$hostname"
  save_state_value USERNAME "$username"
  save_state_value EXTRA_KERNEL_CMDLINE "$extra_kernel_cmdline"
  save_state_value ROOT_PART "$ROOT_PART"
  save_state_value TARGET_DISK "$TARGET_DISK"
  save_state_value ESP_PART_NUM "$ESP_PART_NUM"

  # Copy the chroot script into /root/ inside the target.
  # Do NOT use /tmp — arch-chroot mounts a fresh tmpfs over it, wiping the file.
  install -m 700 "$SCRIPT_DIR/1-system-chroot.sh" /mnt/root/nirium-1-system-chroot.sh

  arch-chroot /mnt env \
    KEYMAP="$keymap" \
    TIMEZONE="$timezone" \
    LOCALE="$locale" \
    HOSTNAME="$hostname" \
    USERNAME="$username" \
    USERNAME_SHELL="$username_shell" \
    ROOT_PASSWORD="$root_password" \
    USER_PASSWORD="$user_password" \
    EXTRA_KERNEL_CMDLINE="$extra_kernel_cmdline" \
    ROOT_PART="$ROOT_PART" \
    TARGET_DISK="$TARGET_DISK" \
    ESP_PART_NUM="$ESP_PART_NUM" \
    /bin/bash /root/nirium-1-system-chroot.sh

  rm -f /mnt/root/nirium-1-system-chroot.sh

  echo
  log "Stage 1 complete"
  echo "Next: sudo bash 2-packages.sh"
  end_stage_logging "1-system"
}

main "$@"
