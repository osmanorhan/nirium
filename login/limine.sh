#!/usr/bin/env bash

# Ensure all Limine loader paths carry the same config.
if [[ -f /mnt/boot/limine.conf ]]; then
  install -Dm644 /mnt/boot/limine.conf /mnt/boot/EFI/arch-limine/limine.conf
  install -Dm644 /mnt/boot/limine.conf /mnt/boot/EFI/BOOT/limine.conf
  install -Dm644 /mnt/boot/limine.conf /mnt/boot/EFI/limine/limine.conf
fi
