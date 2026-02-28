#!/usr/bin/env bash
# nirium stage 1 chroot body
# This file is copied into /mnt/tmp/ by 1-system.sh and executed inside arch-chroot.
# Variables are injected via the 'env' prefix in the arch-chroot call:
#   KEYMAP TIMEZONE LOCALE HOSTNAME USERNAME USERNAME_SHELL
#   ROOT_PASSWORD USER_PASSWORD EXTRA_KERNEL_CMDLINE
#   ROOT_PART SWAP_PART TARGET_DISK ESP_PART_NUM
set -Eeuo pipefail
trap 'echo "ERROR: chroot stage 1 failed at line $LINENO: $BASH_COMMAND" >&2' ERR

# ── Timezone / clock ──────────────────────────────────────────────────────────
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc

# ── Locale ────────────────────────────────────────────────────────────────────
if grep -q "^#$LOCALE UTF-8" /etc/locale.gen; then
  sed -i "s/^#$LOCALE UTF-8/$LOCALE UTF-8/" /etc/locale.gen
elif ! grep -q "^$LOCALE UTF-8" /etc/locale.gen; then
  echo "$LOCALE UTF-8" >> /etc/locale.gen
fi
locale-gen

echo "LANG=$LOCALE" > /etc/locale.conf
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
if command -v localectl > /dev/null 2>&1; then
  localectl set-keymap "$KEYMAP" > /dev/null 2>&1 || true
  # Best-effort XKB sync so SDDM keyboard layout matches console expectations.
  localectl set-x11-keymap "$KEYMAP" > /dev/null 2>&1 || true
fi

# ── Hostname / hosts ──────────────────────────────────────────────────────────
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1 localhost
::1 localhost
127.0.1.1 ${HOSTNAME}.localdomain ${HOSTNAME}
HOSTS

# ── Users ─────────────────────────────────────────────────────────────────────
echo "root:$ROOT_PASSWORD" | chpasswd
# Use the chosen shell if it exists, fall back to /bin/bash.
USER_SHELL="${USERNAME_SHELL:-/bin/zsh}"
[[ -f $USER_SHELL ]] || USER_SHELL="/bin/bash"
if ! id "$USERNAME" > /dev/null 2>&1; then
  useradd -m -G wheel -s "$USER_SHELL" "$USERNAME"
fi
echo "$USERNAME:$USER_PASSWORD" | chpasswd
chown -R "$USERNAME:$USERNAME" "/home/$USERNAME" 2>/dev/null || true

install -d -m 755 /etc/sudoers.d
printf '%%wheel ALL=(ALL:ALL) ALL\n' > /etc/sudoers.d/10-wheel
chmod 440 /etc/sudoers.d/10-wheel

# ── Pacman tweaks ─────────────────────────────────────────────────────────────
if grep -q '^#Color' /etc/pacman.conf; then
  sed -i 's/^#Color/Color/' /etc/pacman.conf
fi
if grep -q '^#VerbosePkgLists' /etc/pacman.conf; then
  sed -i 's/^#VerbosePkgLists/VerbosePkgLists/' /etc/pacman.conf
fi
if grep -q '^#ParallelDownloads' /etc/pacman.conf; then
  sed -i 's/^#ParallelDownloads = .*/ParallelDownloads = 10/' /etc/pacman.conf
elif ! grep -q '^ParallelDownloads' /etc/pacman.conf; then
  echo 'ParallelDownloads = 10' >> /etc/pacman.conf
fi

# ── Kernel cmdline ────────────────────────────────────────────────────────────
ROOT_UUID="$(blkid -s UUID -o value "$ROOT_PART")"
SWAP_UUID="$(blkid -s UUID -o value "$SWAP_PART")"
CMDLINE="root=UUID=$ROOT_UUID rootflags=subvol=@ rw resume=UUID=$SWAP_UUID"
if [[ -n $EXTRA_KERNEL_CMDLINE ]]; then
  CMDLINE="$CMDLINE $EXTRA_KERNEL_CMDLINE"
fi

# ── Limine bootloader ─────────────────────────────────────────────────────────
cat > /etc/default/limine <<LIMINE_DEFAULT
TARGET_OS_NAME="nirium"
ESP_PATH="/boot"
KERNEL_CMDLINE[default]="$CMDLINE"
ENABLE_LIMINE_FALLBACK=yes
FIND_BOOTLOADERS=yes
BOOT_ORDER="*, *fallback, Snapshots"
MAX_SNAPSHOT_ENTRIES=5
SNAPSHOT_FORMAT_CHOICE=5
LIMINE_DEFAULT

install -d /boot/EFI/arch-limine /boot/EFI/BOOT
cp -f /usr/share/limine/BOOTX64.EFI /boot/EFI/arch-limine/BOOTX64.EFI
cp -f /usr/share/limine/BOOTX64.EFI /boot/EFI/BOOT/BOOTX64.EFI

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

efibootmgr --create \
  --disk "$TARGET_DISK" \
  --part "$ESP_PART_NUM" \
  --label "Arch Limine" \
  --loader '\\EFI\\arch-limine\\BOOTX64.EFI' \
  --unicode || true

# Prefer Arch Limine in boot order and remove duplicate Limine entries.
if command -v efibootmgr > /dev/null 2>&1; then
  mapfile -t limine_entries < <(efibootmgr | awk '/Arch Limine/{print substr($1,5,4)}')
  if (( ${#limine_entries[@]} > 0 )); then
    preferred="${limine_entries[0]}"
    if (( ${#limine_entries[@]} > 1 )); then
      for dup in "${limine_entries[@]:1}"; do
        efibootmgr -b "$dup" -B > /dev/null 2>&1 || true
      done
    fi

    boot_order="$(efibootmgr | awk -F': ' '/BootOrder/{print $2}')"
    if [[ -n $boot_order ]]; then
      filtered_order="$(echo "$boot_order" | tr ',' '\n' | awk -v p="$preferred" 'toupper($0)!=toupper(p)' | paste -sd, -)"
      if [[ -n $filtered_order ]]; then
        efibootmgr -o "${preferred},${filtered_order}" > /dev/null 2>&1 || true
      else
        efibootmgr -o "${preferred}" > /dev/null 2>&1 || true
      fi
    fi
  fi
fi

if pacman -Si limine-snapper-sync > /dev/null 2>&1 && pacman -Si limine-mkinitcpio-hook > /dev/null 2>&1; then
  pacman -S --noconfirm --needed limine-snapper-sync limine-mkinitcpio-hook || true
fi

# ── Snapper (Btrfs snapshots) ─────────────────────────────────────────────────
if command -v snapper > /dev/null 2>&1; then
  if ! snapper list-configs 2>/dev/null | grep -Eq '(^|[[:space:]])root([[:space:]]|$)'; then
    umount /.snapshots 2>/dev/null || true
    rm -rf /.snapshots || true
    snapper -c root create-config / || true
    mkdir -p /.snapshots
    mount -a || true
  fi

  if [[ -d /home ]] && ! snapper list-configs 2>/dev/null | grep -Eq '(^|[[:space:]])home([[:space:]]|$)'; then
    snapper -c home create-config /home || true
  fi

  btrfs quota enable / > /dev/null 2>&1 || true
  for cfg in /etc/snapper/configs/root /etc/snapper/configs/home; do
    [[ -f $cfg ]] || continue
    sed -i 's/^TIMELINE_CREATE="yes"/TIMELINE_CREATE="no"/' "$cfg"
    sed -i 's/^NUMBER_LIMIT="50"/NUMBER_LIMIT="5"/' "$cfg"
    sed -i 's/^NUMBER_LIMIT_IMPORTANT="10"/NUMBER_LIMIT_IMPORTANT="5"/' "$cfg"
    sed -i 's/^SPACE_LIMIT="0.5"/SPACE_LIMIT="0.3"/' "$cfg"
    sed -i 's/^FREE_LIMIT="0.2"/FREE_LIMIT="0.3"/' "$cfg"
  done
  systemctl enable snapper-timeline.timer snapper-cleanup.timer || true
fi

# ── Limine refresh helper ─────────────────────────────────────────────────────
install -d /usr/local/bin
cat > /usr/local/bin/nirium-limine-refresh <<'LIMINE_REFRESH'
#!/usr/bin/env bash
set -Eeuo pipefail

[[ -f /boot/limine.conf ]] || exit 0

install -d /boot/EFI/arch-limine /boot/EFI/BOOT
install -Dm644 /boot/limine.conf /boot/EFI/arch-limine/limine.conf
install -Dm644 /boot/limine.conf /boot/EFI/BOOT/limine.conf

if command -v limine-update > /dev/null 2>&1; then
  if ! limine-update; then
    echo "WARN: limine-update failed, using static /boot/limine.conf"
  elif ! grep -q '^/+' /boot/limine.conf; then
    echo "WARN: limine-update did not add generated entries"
  fi
fi

if command -v limine-snapper-sync > /dev/null 2>&1; then
  limine-snapper-sync || true
fi
LIMINE_REFRESH
chmod +x /usr/local/bin/nirium-limine-refresh

if ! grep -q '\bresume\b' /etc/mkinitcpio.conf; then
  sed -i 's/\bfilesystems\b/resume filesystems/' /etc/mkinitcpio.conf
fi
mkinitcpio -P
/usr/local/bin/nirium-limine-refresh || true
if systemctl list-unit-files | grep -q '^limine-snapper-sync.service'; then
  systemctl enable limine-snapper-sync.service || true
fi

# ── Graphical login stack (SDDM + niri session) ───────────────────────────────
# qt6-wayland is required for SDDM to run its greeter under Wayland.
pacman -S --noconfirm --needed sddm qt6-declarative qt6-svg qt6-wayland \
  xorg-server xorg-xauth xorg-xhost xorg-xsetroot xorg-xrdb xorg-xrandr

install -d /usr/local/bin
cat > /usr/local/bin/niri-session-wrapper <<'NIRIWRAP'
#!/usr/bin/env bash
set -Eeuo pipefail

# Ensure standard paths are present regardless of how SDDM spawns us.
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

if command -v lspci > /dev/null 2>&1 && [[ -d /dev/dri/by-path ]]; then
  AMD_BDF="$(lspci -D | awk 'tolower($0) ~ /(vga|3d|display)/ && tolower($0) ~ /amd/ {print $1; exit}')"
  if [[ -n ${AMD_BDF:-} ]]; then
    AMD_DRM="/dev/dri/by-path/pci-${AMD_BDF}-card"
    if [[ -e $AMD_DRM ]]; then
      export WLR_DRM_DEVICES="$AMD_DRM"
    fi
  fi
fi

# Self-heal missing user config so first login is not blocked.
if [[ -n ${HOME:-} ]]; then
  cfg_root="${XDG_CONFIG_HOME:-$HOME/.config}"
  if [[ ! -f "$cfg_root/niri/config.kdl" ]]; then
    mkdir -p "$cfg_root/niri"
    if [[ -f /etc/xdg/niri/config.kdl ]]; then
      cp /etc/xdg/niri/config.kdl "$cfg_root/niri/config.kdl"
    fi
  fi
fi

# Fail fast with a visible journal entry if niri-session is missing.
if ! command -v niri-session > /dev/null 2>&1; then
  echo "niri-session not found in PATH=$PATH" \
    | systemd-cat -t niri-session-wrapper -p err 2>/dev/null || true
  exit 1
fi

exec niri-session
NIRIWRAP
chmod +x /usr/local/bin/niri-session-wrapper

install -d /usr/share/wayland-sessions
cat > /usr/share/wayland-sessions/niri-wrapper.desktop <<'NIRIDESKTOP'
[Desktop Entry]
Name=Niri
Comment=Niri session using installer wrapper
Exec=/usr/local/bin/niri-session-wrapper
Type=Application
DesktopNames=niri
NIRIDESKTOP

# ── SDDM theme ────────────────────────────────────────────────────────────────
install -d /usr/share/sddm/themes/nirium
cat > /usr/share/sddm/themes/nirium/metadata.desktop <<'SDDMMETA'
[SddmGreeterTheme]
Name=Nirium
Description=Minimal black login theme
Author=nirium
Type=sddm-theme
Version=1.0
SDDMMETA

cat > /usr/share/sddm/themes/nirium/theme.conf <<'SDDMCONF'
[General]
SDDMCONF

cat > /usr/share/sddm/themes/nirium/Main.qml <<'SDDMQML'
import QtQuick 2.15

Rectangle {
    id: root
    width: 640
    height: 480
    color: "#000000"

    property int sessionIndex: {
        for (var i = 0; i < sessionModel.rowCount(); i++) {
            var name = (sessionModel.data(sessionModel.index(i, 0), Qt.DisplayRole) || "").toString().toLowerCase()
            if (name.indexOf("niri") !== -1) {
                return i
            }
        }
        return sessionModel.lastIndex
    }

    Column {
        anchors.centerIn: parent
        spacing: root.height * 0.025
        width: root.width * 0.45

        Text {
            text: "nirium"
            color: "#ffffff"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: root.height * 0.042
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Rectangle {
            width: parent.width
            height: root.height * 0.055
            color: "#000000"
            border.color: "#ffffff"
            border.width: 1

            TextInput {
                id: username
                anchors.fill: parent
                anchors.margins: root.height * 0.009
                verticalAlignment: TextInput.AlignVCenter
                color: "#ffffff"
                text: userModel.lastUser
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: root.height * 0.022
                selectByMouse: true
            }
        }

        Rectangle {
            width: parent.width
            height: root.height * 0.055
            color: "#000000"
            border.color: "#ffffff"
            border.width: 1

            TextInput {
                id: password
                anchors.fill: parent
                anchors.margins: root.height * 0.009
                verticalAlignment: TextInput.AlignVCenter
                color: "#ffffff"
                echoMode: TextInput.Password
                passwordCharacter: "\u2022"
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: root.height * 0.022
                selectByMouse: true

                Keys.onPressed: {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        sddm.login(username.text, password.text, root.sessionIndex)
                        event.accepted = true
                    }
                }
            }
        }

        Text {
            id: errorMessage
            text: ""
            color: "#f7768e"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: root.height * 0.019
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            errorMessage.text = "Login failed"
            password.text = ""
            password.focus = true
        }
        function onLoginSucceeded() {
            errorMessage.text = ""
        }
    }

    Component.onCompleted: {
        if (username.text.length > 0) {
            password.forceActiveFocus()
        } else {
            username.forceActiveFocus()
        }
    }
}
SDDMQML

# ── SDDM config ───────────────────────────────────────────────────────────────
install -d /etc/sddm.conf.d
cat > /etc/sddm.conf.d/10-nirium.conf <<SDDMSYSTEM
[General]
DisplayServer=wayland
Numlock=on
SessionDir=/usr/share/wayland-sessions:/usr/share/xsessions

[Autologin]
User=$USERNAME
Session=niri-wrapper
Relogin=false

[Theme]
Current=nirium
SDDMSYSTEM

# ── Passwordless keyring (avoid first-login prompts) ──────────────────────────
KEYRING_DIR="/home/$USERNAME/.local/share/keyrings"
KEYRING_FILE="$KEYRING_DIR/Default_keyring.keyring"
KEYRING_DEFAULT_FILE="$KEYRING_DIR/default"
install -d -m 700 "$KEYRING_DIR"
cat > "$KEYRING_FILE" <<EOF
[keyring]
display-name=Default keyring
ctime=$(date +%s)
mtime=0
lock-on-idle=false
lock-after=false
EOF
echo "Default_keyring" > "$KEYRING_DEFAULT_FILE"
chmod 600 "$KEYRING_FILE"
chmod 644 "$KEYRING_DEFAULT_FILE"
chown -R "$USERNAME:$USERNAME" "$KEYRING_DIR"

# ── PAM hardening ─────────────────────────────────────────────────────────────
# Prevent SDDM password flow from creating encrypted keyrings unexpectedly.
if [[ -f /etc/pam.d/sddm ]]; then
  sed -i '/pam_gnome_keyring\.so/d' /etc/pam.d/sddm
fi
if [[ -f /etc/pam.d/sddm-autologin ]]; then
  sed -i '/pam_gnome_keyring\.so/d' /etc/pam.d/sddm-autologin
  # NOTE: Do NOT inject pam_faillock into sddm-autologin — it breaks autologin
  # when any previous failed-login counter exists for the user.
fi

# Avoid spurious org.freedesktop.home1 activation failures on non-homed setups.
for pam_file in /etc/pam.d/system-auth /etc/pam.d/system-login /etc/pam.d/sddm /etc/pam.d/sddm-autologin; do
  if [[ -f $pam_file ]]; then
    sed -i '/pam_systemd_home\.so/d' "$pam_file"
  fi
done

install -d /etc/security
cat > /etc/security/faillock.conf <<'FAILLOCK'
deny = 8
unlock_time = 120
FAILLOCK

if passwd -S "$USERNAME" 2>/dev/null | awk '{print $2}' | grep -q '^L$'; then
  passwd -u "$USERNAME" > /dev/null 2>&1 || true
fi

# ── Kernel / sysctl tuning ────────────────────────────────────────────────────
install -d /etc/sysctl.d
echo 'fs.inotify.max_user_watches=524288' > /etc/sysctl.d/90-nirium.conf
echo 'vm.swappiness=10' >> /etc/sysctl.d/90-nirium.conf
sysctl --system > /dev/null 2>&1 || true

# ── Systemd tuning ────────────────────────────────────────────────────────────
install -d /etc/systemd/system.conf.d
cat > /etc/systemd/system.conf.d/10-fast-shutdown.conf <<'SYSCFG'
[Manager]
DefaultTimeoutStopSec=10s
SYSCFG

install -d /etc/systemd/system/user@.service.d
cat > /etc/systemd/system/user@.service.d/10-fast-shutdown.conf <<'USERCFG'
[Service]
TimeoutStopSec=10s
USERCFG

# ── Hardware quirks ───────────────────────────────────────────────────────────
if [[ ! -f /etc/modprobe.d/disable-usb-autosuspend.conf ]]; then
  echo 'options usbcore autosuspend=-1' > /etc/modprobe.d/disable-usb-autosuspend.conf
fi

if [[ ! -e /etc/resolv.conf || ! /etc/resolv.conf -ef /run/systemd/resolve/stub-resolv.conf ]]; then
  ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
fi

# ── UFW firewall ──────────────────────────────────────────────────────────────
cat > /usr/local/bin/nirium-ufw-setup <<'UFWSETUP'
#!/usr/bin/env bash
set -Eeuo pipefail

ufw default deny incoming || true
ufw default allow outgoing || true
ufw allow 53317/udp || true
ufw allow 53317/tcp || true
ufw --force enable || true
UFWSETUP
chmod +x /usr/local/bin/nirium-ufw-setup

cat > /etc/systemd/system/nirium-ufw-firstboot.service <<'UFWUNIT'
[Unit]
Description=Apply UFW baseline on first boot
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/nirium-ufw-setup

[Install]
WantedBy=multi-user.target
UFWUNIT

if [[ -d /lib/modules/"$(uname -r)" || -d /usr/lib/modules/"$(uname -r)" ]]; then
  /usr/local/bin/nirium-ufw-setup || true
else
  systemctl enable nirium-ufw-firstboot.service
fi

# ── Services ──────────────────────────────────────────────────────────────────
systemctl enable NetworkManager.service
systemctl enable systemd-resolved.service
systemctl enable bluetooth.service
systemctl disable greetd.service || true
systemctl mask greetd.service || true
systemctl enable sddm.service
systemctl enable ufw.service
systemctl set-default graphical.target || true
systemctl enable power-profiles-daemon.service || true

# Enable Pipewire audio stack globally for all users (needed by niri-session).
# Note: enable the SOCKET for pipewire-pulse (socket-activated), not the service.
systemctl --global enable pipewire.service pipewire-pulse.socket wireplumber.service || true

# Enable iwd (modern WiFi backend) and configure NetworkManager to use it.
systemctl enable iwd.service || true
install -d /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/wifi-backend.conf <<'NMCONF'
[device]
wifi.backend=iwd
NMCONF

# ── Wayland environment ───────────────────────────────────────────────────────
# NOTE: XDG_SESSION_TYPE is intentionally NOT set here — SDDM sets it
# automatically per-session. Setting it globally breaks TTY logins.
cat > /etc/environment <<'ENVFILE'
QT_QPA_PLATFORM=wayland
QT_WAYLAND_DISABLE_WINDOWDECORATION=1
GDK_BACKEND=wayland,x11
ELECTRON_OZONE_PLATFORM_HINT=auto
MOZ_ENABLE_WAYLAND=1
ENVFILE
