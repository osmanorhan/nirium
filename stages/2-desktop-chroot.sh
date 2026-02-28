#!/usr/bin/env bash
# nirium stage 2 chroot body
# This file is copied into /mnt/tmp/ by 2-desktop.sh and executed inside arch-chroot.
# Variables injected via 'env': USERNAME ROOT_PART SWAP_PART EXTRA_KERNEL_CMDLINE
set -Eeuo pipefail
trap 'echo "ERROR: chroot stage 2 failed at line $LINENO: $BASH_COMMAND" >&2' ERR

if ! id "$USERNAME" > /dev/null 2>&1; then
  echo "User does not exist: $USERNAME" >&2
  exit 1
fi

# ── GPU detection ─────────────────────────────────────────────────────────────
GPU_LINES="$(lspci | grep -iE '(VGA|3D|Display)' || true)"
HAS_NVIDIA=0
HAS_AMD=0
HAS_INTEL=0
if echo "$GPU_LINES" | grep -qi 'NVIDIA'; then HAS_NVIDIA=1; fi
if echo "$GPU_LINES" | grep -qi 'AMD';    then HAS_AMD=1;    fi
if echo "$GPU_LINES" | grep -qi 'Intel';  then HAS_INTEL=1;  fi

VULKAN_PACKAGES=()
if (( HAS_INTEL == 1 )); then VULKAN_PACKAGES+=(vulkan-intel);  fi
if (( HAS_AMD   == 1 )); then VULKAN_PACKAGES+=(vulkan-radeon); fi
if (( ${#VULKAN_PACKAGES[@]} > 0 )); then
  pacman -S --noconfirm --needed "${VULKAN_PACKAGES[@]}"
fi

# ── Kernel cmdline ────────────────────────────────────────────────────────────
ROOT_UUID="$(blkid -s UUID -o value "$ROOT_PART")"
SWAP_UUID="$(blkid -s UUID -o value "$SWAP_PART")"
CMDLINE="root=UUID=$ROOT_UUID rootflags=subvol=@ rw resume=UUID=$SWAP_UUID"
if [[ -n $EXTRA_KERNEL_CMDLINE ]]; then
  CMDLINE="$CMDLINE $EXTRA_KERNEL_CMDLINE"
fi

# ── NVIDIA drivers ────────────────────────────────────────────────────────────
if (( HAS_NVIDIA == 1 )); then
  pacman -S --noconfirm --needed linux-headers nvidia-open-dkms nvidia-utils libva-nvidia-driver || \
    pacman -S --noconfirm --needed linux-headers nvidia-dkms nvidia-utils libva-nvidia-driver

  if (( HAS_AMD == 1 || HAS_INTEL == 1 )); then
    mkdir -p /etc/modprobe.d
    echo 'options nvidia_drm modeset=0' > /etc/modprobe.d/nvidia-compute-only.conf
  else
    mkdir -p /etc/modprobe.d /etc/mkinitcpio.conf.d
    echo 'options nvidia_drm modeset=1' > /etc/modprobe.d/nvidia.conf
    cat > /etc/mkinitcpio.conf.d/nvidia.conf <<'NVIDIAMK'
MODULES+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
NVIDIAMK

    if [[ $CMDLINE != *'nvidia-drm.modeset=1'* ]]; then
      CMDLINE="$CMDLINE nvidia-drm.modeset=1"
    fi
  fi

  if systemctl list-unit-files | grep -q '^nvidia-persistenced.service'; then
    systemctl enable nvidia-persistenced.service
  fi
fi

# ── Limine update for GPU-adjusted cmdline ────────────────────────────────────
cat > /boot/limine.conf <<LIMINE
timeout: 5

/Arch Linux
    protocol: linux
    path: boot():/vmlinuz-linux
    cmdline: $CMDLINE
    module_path: boot():/initramfs-linux.img
LIMINE
install -Dm644 /boot/limine.conf /boot/EFI/arch-limine/limine.conf
install -Dm644 /boot/limine.conf /boot/EFI/BOOT/limine.conf

if [[ -f /etc/default/limine ]]; then
  ESCAPED_CMDLINE="${CMDLINE//&/\\&}"
  sed -i "s|^KERNEL_CMDLINE\\[default\\]=.*|KERNEL_CMDLINE[default]=\"$ESCAPED_CMDLINE\"|" /etc/default/limine || true
fi

mkinitcpio -P
if command -v nirium-limine-refresh > /dev/null 2>&1; then
  nirium-limine-refresh || true
fi

# ── AUR helper (yay) ──────────────────────────────────────────────────────────
pacman -S --noconfirm --needed git base-devel

if ! command -v yay > /dev/null 2>&1; then
  YAY_PKG="$(sudo -u "$USERNAME" bash -lc '
    set -Eeuo pipefail
    workdir="$(mktemp -d)"
    cd "$workdir"
    git clone https://aur.archlinux.org/yay-bin.git >&2
    cd yay-bin
    makepkg -s --noconfirm >&2
    pkg="$(ls -1 *.pkg.tar.* | head -n1)"
    printf "%s" "$workdir/yay-bin/$pkg"
  ')"
  if [[ -z $YAY_PKG || ! -f $YAY_PKG ]]; then
    echo "Unable to build yay package" >&2
    exit 1
  fi
  pacman -U --noconfirm "$YAY_PKG"
fi

# ── Desktop shell (modular — no DMS) ─────────────────────────────────────────
# waybar, swaync, fuzzel, swaybg, lxsession are installed via desktop.pacman.
# They are started directly from ~/.config/niri/config.kdl via spawn-at-startup.

# ── AUR GTK theme ─────────────────────────────────────────────────────────────
# adw-gtk3 is AUR-only — install via yay (non-blocking).
sudo -u "$USERNAME" bash -lc 'yay -S --noconfirm --needed adw-gtk3 papirus-icon-theme' || \
  echo 'WARN: adw-gtk3 (AUR GTK theme) failed; GTK apps will use default theme' >&2

# ── First-run onboarding ──────────────────────────────────────────────────────
cat > /usr/local/bin/nirium-first-run <<'FIRST_RUN'
#!/usr/bin/env bash
set -Eeuo pipefail

home_dir="${HOME:-}"
if [[ -z $home_dir ]]; then
  home_dir="$(getent passwd "$(id -un)" | cut -d: -f6)"
fi
[[ -n $home_dir ]] || exit 0

state_root="${XDG_STATE_HOME:-$home_dir/.local/state}"
state_dir="$state_root/nirium"
marker="$state_dir/first-run.done"
mkdir -p "$state_dir" 2>/dev/null || exit 0
[[ -f $marker ]] && exit 0

notify() {
  if command -v notify-send > /dev/null 2>&1; then
    notify-send "$1" "$2" -u normal > /dev/null 2>&1 || true
  fi
}

notify "Welcome to nirium" "Super+D launcher, Super+Return terminal."

if command -v ping > /dev/null 2>&1 && ! ping -c1 -W1 1.1.1.1 > /dev/null 2>&1; then
  notify "Wi-Fi setup" "No internet detected. Click the network icon in the DMS bar."
else
  notify "Network ready" "Internet looks good."
fi

if command -v systemctl > /dev/null 2>&1 && systemctl is-active --quiet bluetooth.service 2>/dev/null; then
  if command -v bluetoothctl > /dev/null 2>&1 && bluetoothctl show 2>/dev/null | grep -q 'Powered: yes'; then
    notify "Bluetooth ready" "Manage devices via the Bluetooth icon in the DMS bar."
  else
    notify "Bluetooth off" "Click the Bluetooth icon in the DMS bar to enable."
  fi
fi

touch "$marker" 2>/dev/null || true
FIRST_RUN
chmod +x /usr/local/bin/nirium-first-run

install -d -m 700 -o "$USERNAME" -g "$USERNAME" "/home/$USERNAME/.config/systemd/user/default.target.wants"
cat > "/home/$USERNAME/.config/systemd/user/nirium-first-run.service" <<'FIRST_RUN_UNIT'
[Unit]
Description=nirium first-run onboarding
After=graphical-session.target
Wants=graphical-session.target
ConditionPathExists=!%h/.local/state/nirium/first-run.done

[Service]
Type=oneshot
Environment=HOME=%h
Environment=XDG_STATE_HOME=%h/.local/state
WorkingDirectory=%h
ExecStart=/usr/local/bin/nirium-first-run

[Install]
WantedBy=default.target
FIRST_RUN_UNIT
if [[ ! -e "/home/$USERNAME/.config/systemd/user/default.target.wants/nirium-first-run.service" ]]; then
  ln -s ../nirium-first-run.service "/home/$USERNAME/.config/systemd/user/default.target.wants/nirium-first-run.service"
fi
chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.config/systemd/user"

# ── Boot sanity checks (fail early, before reboot) ────────────────────────────
required_boot_files=(
  /boot/limine.conf
  /boot/EFI/arch-limine/BOOTX64.EFI
  /boot/EFI/BOOT/BOOTX64.EFI
  /boot/EFI/arch-limine/limine.conf
  /boot/EFI/BOOT/limine.conf
  /boot/vmlinuz-linux
  /boot/initramfs-linux.img
)
for f in "${required_boot_files[@]}"; do
  if [[ ! -f $f ]]; then
    echo "Missing required boot file: $f" >&2
    exit 1
  fi
done
if ! grep -q '^[[:space:]]*cmdline:' /boot/limine.conf; then
  echo "Missing cmdline in /boot/limine.conf" >&2
  exit 1
fi

# ── Login/session sanity checks ───────────────────────────────────────────────
required_login_files=(
  /usr/lib/systemd/system/sddm.service
  /usr/bin/sddm-greeter-qt6
  /usr/share/wayland-sessions/niri-wrapper.desktop
  /usr/local/bin/niri-session-wrapper
  /etc/sddm.conf.d/10-nirium.conf
)
for f in "${required_login_files[@]}"; do
  if [[ ! -f $f ]]; then
    echo "Missing required login file: $f" >&2
    exit 1
  fi
done
if ! systemctl is-enabled sddm.service > /dev/null 2>&1; then
  echo "sddm.service is not enabled" >&2
  exit 1
fi
if ! grep -q '^Session=niri-wrapper$' /etc/sddm.conf.d/10-nirium.conf 2>/dev/null; then
  echo "SDDM autologin session is not set to niri-wrapper" >&2
  exit 1
fi
if [[ -L /etc/systemd/system/default.target ]]; then
  if [[ "$(readlink /etc/systemd/system/default.target)" != *graphical.target ]]; then
    echo "default.target is not graphical.target" >&2
    exit 1
  fi
fi
