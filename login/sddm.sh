#!/usr/bin/env bash

# Reinforce login stack for non-homed systems.
# If /mnt is mounted (installer context), patch /mnt; otherwise patch live /.
target_root="/"
if command -v findmnt >/dev/null 2>&1 && findmnt -M /mnt >/dev/null 2>&1 && [[ -d /mnt/etc/pam.d ]]; then
  target_root="/mnt"
fi

for pam_file in \
  "$target_root/etc/pam.d/system-auth" \
  "$target_root/etc/pam.d/system-login" \
  "$target_root/etc/pam.d/sddm" \
  "$target_root/etc/pam.d/sddm-autologin"; do
  [[ -f $pam_file ]] || continue
  sed -i '/pam_systemd_home\.so/d' "$pam_file"
done
