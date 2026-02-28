#!/usr/bin/env bash

# Ensure fallback and explicit limine paths both carry the same config.
if [[ -f /mnt/boot/limine.conf ]]; then
  install -Dm644 /mnt/boot/limine.conf /mnt/boot/EFI/arch-limine/limine.conf
  install -Dm644 /mnt/boot/limine.conf /mnt/boot/EFI/BOOT/limine.conf
fi
