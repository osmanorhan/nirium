#!/usr/bin/env bash

set -Eeuo pipefail

STATE_FILE_DEFAULT="/mnt/etc/nirium-install.env"
INSTALL_LOG_FILE_DEFAULT="/var/log/nirium-installer.log"
ROOT_PART=""
TARGET_DISK=""
ESP_PART=""
ESP_PART_NUM=""
STAGE_NAME=""

log() {
  printf '==> %s\n' "$*"
}

warn() {
  printf 'WARN: %s\n' "$*" >&2
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

begin_stage_logging() {
  local stage_name="$1"
  local log_file="${2:-$INSTALL_LOG_FILE_DEFAULT}"

  STAGE_NAME="$stage_name"
  touch "$log_file" 2>/dev/null || true
  chmod 0644 "$log_file" 2>/dev/null || true
  exec > >(tee -a "$log_file") 2>&1

  log "[$STAGE_NAME] started at $(date '+%Y-%m-%d %H:%M:%S')"
  log "[$STAGE_NAME] logging to $log_file"
}

end_stage_logging() {
  local stage_name="${1:-$STAGE_NAME}"
  log "[$stage_name] completed at $(date '+%Y-%m-%d %H:%M:%S')"
}

on_stage_error() {
  local stage_name="$1"
  local line="$2"
  local cmd="$3"

  printf 'ERROR: [%s] failed at line %s\n' "$stage_name" "$line" >&2
  printf 'ERROR: [%s] command: %s\n' "$stage_name" "$cmd" >&2
  printf 'ERROR: [%s] see full log: %s\n' "$stage_name" "$INSTALL_LOG_FILE_DEFAULT" >&2
}

require_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    die "Run as root (example: sudo bash $0)"
  fi
}

require_cmds() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      die "Missing command: $cmd"
    fi
  done
}

ensure_uefi() {
  [[ -d /sys/firmware/efi ]] || die "UEFI firmware not detected. BIOS installs are not supported."
}

prompt_default() {
  local label="$1"
  local default="$2"
  local out=""
  read -r -p "$label [$default]: " out || true
  if [[ -z $out ]]; then
    printf '%s\n' "$default"
  else
    printf '%s\n' "$out"
  fi
}

prompt_secret_confirm() {
  local label="$1"
  local p1=""
  local p2=""

  while true; do
    read -r -s -p "$label: " p1
    printf '\n' >&2
    read -r -s -p "Confirm $label: " p2
    printf '\n' >&2

    if [[ -z $p1 ]]; then
      warn "Password cannot be empty."
      continue
    fi

    if [[ $p1 != "$p2" ]]; then
      warn "Passwords do not match."
      continue
    fi

    printf '%s\n' "$p1"
    return 0
  done
}

read_package_file() {
  local package_file="$1"
  [[ -f $package_file ]] || die "Package file not found: $package_file"

  mapfile -t PKG_LIST < <(grep -vE '^[[:space:]]*(#|$)' "$package_file")
  (( ${#PKG_LIST[@]} > 0 )) || die "Package file is empty: $package_file"
}

disk_part_path() {
  local disk="$1"
  local number="$2"

  if [[ $disk =~ (nvme|mmcblk|loop) ]]; then
    printf '%sp%s\n' "$disk" "$number"
  else
    printf '%s%s\n' "$disk" "$number"
  fi
}

show_disks() {
  echo
  echo "Available disks:"
  lsblk -d -o PATH,SIZE,MODEL,TYPE | awk '$4=="disk" {print "  "$1"  "$2"  "$3}'
  echo
}

first_disk() {
  local d=""
  d="$(lsblk -dnpo PATH,TYPE,RM | awk '$2=="disk" && $3==0 {print $1; exit}')"
  if [[ -n $d ]]; then
    printf '%s\n' "$d"
    return 0
  fi

  lsblk -dnpo PATH,TYPE | awk '$2=="disk" {print $1; exit}'
}

detect_ram_gib() {
  local mem_kib
  mem_kib="$(awk '/MemTotal:/ {print $2}' /proc/meminfo)"
  printf '%s\n' "$(( (mem_kib + 1024 * 1024 - 1) / (1024 * 1024) ))"
}

resolve_device_spec() {
  local spec="$1"

  case "$spec" in
    UUID=*)
      readlink -f "/dev/disk/by-uuid/${spec#UUID=}" || true
      ;;
    PARTUUID=*)
      readlink -f "/dev/disk/by-partuuid/${spec#PARTUUID=}" || true
      ;;
    /dev/*)
      printf '%s\n' "$spec"
      ;;
    *)
      printf '\n'
      ;;
  esac
}

mount_target_layout() {
  local root_part="$1"
  local esp_part="$2"

  mount -o subvol=@,compress=zstd,noatime "$root_part" /mnt
  mkdir -p /mnt/{boot,home,.snapshots,var/log,swap}
  mount -o subvol=@home,compress=zstd,noatime "$root_part" /mnt/home
  mount -o subvol=@snapshots,compress=zstd,noatime "$root_part" /mnt/.snapshots
  mount -o subvol=@var_log,compress=zstd,noatime "$root_part" /mnt/var/log
  mount -o subvol=@swap,compress=zstd,noatime "$root_part" /mnt/swap
  mount "$esp_part" /mnt/boot
}

ensure_target_mounted() {
  local root_part=""
  local disk_input=""
  local root_candidates=()
  local root_count=0
  local guessed_esp=""

  if ! mountpoint -q /mnt; then
    mapfile -t root_candidates < <(lsblk -P -rno PATH,PARTLABEL | awk -F'"' 'tolower($4) ~ /linux[ -]?root|^root$/ {print $2}')
    root_count=${#root_candidates[@]}

    if (( root_count == 1 )); then
      root_part="${root_candidates[0]}"
      log "Detected root partition: $root_part"
    else
      show_disks
      disk_input="$(prompt_default "Target disk (contains Linux root partition)" "$(first_disk)")"
      [[ -b $disk_input ]] || die "Disk not found: $disk_input"
      root_part="$(disk_part_path "$disk_input" 3)"
    fi

    [[ -b $root_part ]] || die "Root partition not found: $root_part"

    TARGET_DISK="/dev/$(lsblk -no pkname "$root_part" | head -n1)"
    [[ -b $TARGET_DISK ]] || die "Could not detect target disk from root partition: $root_part"

    guessed_esp="$(disk_part_path "$TARGET_DISK" 1)"

    mount -o subvol=@,compress=zstd,noatime "$root_part" /mnt
    mkdir -p /mnt/{boot,home,.snapshots,var/log,swap}
    mount -o subvol=@home,compress=zstd,noatime "$root_part" /mnt/home || true
    mount -o subvol=@snapshots,compress=zstd,noatime "$root_part" /mnt/.snapshots || true
    mount -o subvol=@var_log,compress=zstd,noatime "$root_part" /mnt/var/log || true
    mount -o subvol=@swap,compress=zstd,noatime "$root_part" /mnt/swap || true

    if [[ -b $guessed_esp ]]; then
      mount "$guessed_esp" /mnt/boot || true
    fi

    if [[ -f /mnt/swap/swapfile ]] && ! swapon --noheadings --show=NAME | grep -qx "/mnt/swap/swapfile"; then
      swapon /mnt/swap/swapfile || true
    fi
  fi

  if [[ ! -f /mnt/etc/fstab && -d /mnt/etc ]]; then
    genfstab -U /mnt > /mnt/etc/fstab
  fi

  [[ -f /mnt/etc/fstab ]] || die "Missing /mnt/etc/fstab. Run stage 0 first."
}

read_target_context() {
  local root_part_raw=""
  local esp_spec=""

  root_part_raw="$(findmnt -no SOURCE /mnt || true)"
  [[ -n $root_part_raw ]] || die "Could not detect source for /mnt"

  ROOT_PART="${root_part_raw%%\[*}"
  if [[ $ROOT_PART == UUID=* || $ROOT_PART == PARTUUID=* ]]; then
    ROOT_PART="$(resolve_device_spec "$ROOT_PART")"
  fi

  [[ $ROOT_PART == /dev/* ]] || ROOT_PART="/${ROOT_PART#/}"
  [[ -b $ROOT_PART ]] || die "Invalid root block device: $ROOT_PART"

  TARGET_DISK="/dev/$(lsblk -no pkname "$ROOT_PART" | head -n1)"
  [[ -b $TARGET_DISK ]] || die "Could not detect target disk from root partition: $ROOT_PART"

  ESP_PART="$(findmnt -no SOURCE /mnt/boot || true)"
  if [[ -z $ESP_PART ]]; then
    esp_spec="$(awk '$2=="/boot" {print $1; exit}' /mnt/etc/fstab)"
    if [[ -n $esp_spec ]]; then
      ESP_PART="$(resolve_device_spec "$esp_spec")"
    fi
  fi

  if [[ -z $ESP_PART || ! -b $ESP_PART ]]; then
    ESP_PART="$(disk_part_path "$TARGET_DISK" 1)"
  fi
  [[ -b $ESP_PART ]] || die "Could not resolve ESP device"

  if ! mountpoint -q /mnt/boot; then
    mkdir -p /mnt/boot
    mount "$ESP_PART" /mnt/boot
  fi

  if [[ -f /mnt/swap/swapfile ]] && ! swapon --noheadings --show=NAME | grep -qx "/mnt/swap/swapfile"; then
    swapon /mnt/swap/swapfile || true
  fi

  ESP_PART_NUM="$(lsblk -no PARTN "$ESP_PART" | head -n1)"
  [[ -n $ESP_PART_NUM ]] || die "Could not detect ESP partition number from $ESP_PART"
}

save_state_value() {
  local key="$1"
  local value="$2"
  local state_file="${3:-$STATE_FILE_DEFAULT}"
  local escaped=""
  local tmp_file=""

  escaped=${value//\"/\\\"}
  tmp_file="$(mktemp)"

  if [[ -f $state_file ]]; then
    awk -v k="$key" -v v="$escaped" '
      BEGIN { done=0 }
      $0 ~ ("^" k "=") {
        print k "=\"" v "\""
        done=1
        next
      }
      { print }
      END {
        if (!done) {
          print k "=\"" v "\""
        }
      }
    ' "$state_file" > "$tmp_file"
  else
    printf '%s="%s"\n' "$key" "$escaped" > "$tmp_file"
  fi

  install -Dm600 "$tmp_file" "$state_file"
  rm -f "$tmp_file"
}

read_state_value() {
  local key="$1"
  local state_file="${2:-$STATE_FILE_DEFAULT}"

  if [[ ! -f $state_file ]]; then
    printf '\n'
    return 0
  fi

  awk -F= -v k="$key" '
    $1 == k {
      v=$2
      gsub(/^"/, "", v)
      gsub(/"$/, "", v)
      print v
      exit
    }
  ' "$state_file"
}
