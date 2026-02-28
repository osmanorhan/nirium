#!/usr/bin/env bash

[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "Run as root (sudo)." >&2; exit 1; }
[[ -f /etc/arch-release ]] || { echo "Arch base environment required." >&2; exit 1; }
[[ -d /sys/firmware/efi ]] || { echo "UEFI firmware required." >&2; exit 1; }
