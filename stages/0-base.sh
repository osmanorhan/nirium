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
Stage 0: disk prep + base pacstrap

Usage:
  sudo bash 0-base.sh [options]

Options:
  --disk /dev/nvme0n1   Target install disk
  --swap-gib 32         Override auto swap size in GiB
  --yes                 Skip WIPE confirmation prompt
  -h, --help            Show help
USAGE
}

main() {
  local disk=""
  local swap_gib=""
  local assume_yes=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --disk)
        disk="$2"
        shift 2
        ;;
      --swap-gib)
        swap_gib="$2"
        shift 2
        ;;
      --yes)
        assume_yes=1
        shift
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

  begin_stage_logging "0-base"
  trap 'on_stage_error "0-base" "$LINENO" "$BASH_COMMAND"' ERR

  require_root
  ensure_uefi
  require_cmds lsblk sgdisk partprobe udevadm wipefs mkfs.fat mkfs.btrfs mkswap swapon \
    btrfs mount umount pacstrap genfstab timedatectl

  log "Stage 0: base install (partition + mount + pacstrap)"
  log "Ensure network is up first (example: iwctl)."
  timedatectl set-ntp true

  if mountpoint -q /mnt; then
    die "/mnt is already mounted. Unmount first: umount -R /mnt"
  fi

  local default_disk=""
  local ram_gib=""
  local disk_size_bytes=""
  local disk_gib=""
  local max_swap_gib=0
  local min_root_gib=16
  local required_gib=0
  default_disk="$(first_disk)"
  ram_gib="$(detect_ram_gib)"

  if [[ -z $disk ]]; then
    show_disks
    disk="$(prompt_default "Install disk (WILL BE ERASED)" "$default_disk")"
  fi

  [[ -b $disk ]] || die "Disk not found: $disk"

  disk_size_bytes="$(lsblk -bdno SIZE "$disk")"
  [[ -n $disk_size_bytes ]] || die "Could not detect disk size for $disk"
  disk_gib=$(( disk_size_bytes / 1024 / 1024 / 1024 ))
  max_swap_gib=$(( disk_gib - 1 - min_root_gib ))

  if (( max_swap_gib < 1 )); then
    die "Disk ${disk} is too small (${disk_gib} GiB). Need at least 18 GiB for EFI + swap + root."
  fi

  if [[ -z $swap_gib ]]; then
    swap_gib="$ram_gib"
    if (( swap_gib > max_swap_gib )); then
      swap_gib="$max_swap_gib"
      warn "RAM is larger than available swap space on this disk; using ${swap_gib} GiB swap."
    fi
    log "Auto-selected swap size: ${swap_gib} GiB"
  fi

  if [[ ! $swap_gib =~ ^[0-9]+$ ]] || (( swap_gib < 1 )); then
    die "Invalid --swap-gib value: $swap_gib"
  fi

  if (( swap_gib > max_swap_gib )); then
    die "Requested swap (${swap_gib} GiB) is too large for disk ${disk} (${disk_gib} GiB). Maximum safe swap is ${max_swap_gib} GiB."
  fi

  required_gib=$(( 1 + swap_gib + min_root_gib ))
  if (( disk_gib < required_gib )); then
    die "Disk ${disk} is too small (${disk_gib} GiB). Need at least ${required_gib} GiB for 1 GiB EFI + ${swap_gib} GiB swap + ${min_root_gib} GiB root."
  fi

  if (( assume_yes == 0 )); then
    echo
    echo "This will erase: $disk"
    read -r -p "Type WIPE to continue: " confirm
    [[ $confirm == "WIPE" ]] || die "Aborted by user"
  fi

  local esp_part_num=1
  local swap_part_num=2
  local root_part_num=3
  local esp_part=""
  local swap_part=""
  local root_part=""

  log "Partitioning $disk"
  wipefs -af "$disk"
  sgdisk --zap-all "$disk"
  sgdisk -o "$disk"
  sgdisk -n 1:0:+1G -t 1:ef00 -c 1:EFI-SYSTEM "$disk"
  sgdisk -n 2:0:+"${swap_gib}"G -t 2:8200 -c 2:linux-swap "$disk"
  sgdisk -n 3:0:0 -t 3:8304 -c 3:linux-root "$disk"
  partprobe "$disk"
  udevadm settle

  esp_part="$(disk_part_path "$disk" "$esp_part_num")"
  swap_part="$(disk_part_path "$disk" "$swap_part_num")"
  root_part="$(disk_part_path "$disk" "$root_part_num")"

  [[ -b $esp_part ]] || die "ESP partition not found: $esp_part"
  [[ -b $swap_part ]] || die "Swap partition not found: $swap_part"
  [[ -b $root_part ]] || die "Root partition not found: $root_part"

  log "Formatting partitions"
  mkfs.fat -F 32 "$esp_part"
  mkfs.btrfs -f "$root_part"
  mkswap "$swap_part"
  swapon "$swap_part"

  log "Creating Btrfs subvolumes"
  mount "$root_part" /mnt
  btrfs subvolume create /mnt/@
  btrfs subvolume create /mnt/@home
  btrfs subvolume create /mnt/@snapshots
  btrfs subvolume create /mnt/@var_log
  umount /mnt

  log "Mounting target filesystem"
  mount_target_layout "$root_part" "$esp_part"

  local packages_file="$SCRIPT_DIR/../packages/base.pacman"
  local PKG_LIST=()
  read_package_file "$packages_file"

  log "Installing base packages"
  pacstrap -K /mnt "${PKG_LIST[@]}"

  log "Generating /etc/fstab"
  genfstab -U /mnt > /mnt/etc/fstab

  save_state_value TARGET_DISK "$disk"
  save_state_value ESP_PART_NUM "$esp_part_num"
  save_state_value SWAP_PART "$swap_part"
  save_state_value ROOT_PART "$root_part"

  echo
  log "Stage 0 complete"
  echo "Next: sudo bash 1-settings.sh"
  end_stage_logging "0-base"
}

main "$@"
