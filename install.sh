#!/usr/bin/env bash

set -Eeuo pipefail

OMN_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OMN_MODE="${1:-all}"
if [[ $# -gt 0 ]]; then
  shift
fi

source "$OMN_PATH/helpers/all.sh"
source "$OMN_PATH/preflight/all.sh"
source "$OMN_PATH/packaging/all.sh"
source "$OMN_PATH/config/all.sh"
source "$OMN_PATH/login/all.sh"
source "$OMN_PATH/post-install/all.sh"

trap catch_errors ERR

usage() {
  cat <<'USAGE'
nirium installer

Usage:
  sudo bash install.sh [mode] [args]

Modes:
  all         preflight -> packaging -> config -> login -> post-install
  preflight   run only preflight checks
  packaging   run only base packaging/disk stage
  config      run only system config stage
  login       run only login polish checks/fixes (auto: /mnt if mounted, else /)
  post        run only desktop/post stage

Examples:
  sudo bash install.sh all
  sudo bash install.sh packaging --disk /dev/nvme0n1
  sudo bash install.sh config --user osman
USAGE
}

main() {
  case "$OMN_MODE" in
    all)
      start_install_log
      run_preflight
      run_packaging
      run_config
      run_login
      run_post_install
      ;;
    preflight)
      start_install_log
      run_preflight
      ;;
    packaging|base)
      start_install_log
      if [[ ${1:-} != "-h" && ${1:-} != "--help" ]]; then
        run_preflight
      fi
      run_packaging "$@"
      ;;
    config|system)
      start_install_log
      if [[ ${1:-} != "-h" && ${1:-} != "--help" ]]; then
        run_preflight
      fi
      run_config "$@"
      ;;
    login)
      start_install_log
      run_preflight
      run_login
      ;;
    post|desktop)
      start_install_log
      if [[ ${1:-} != "-h" && ${1:-} != "--help" ]]; then
        run_preflight
      fi
      run_post_install "$@"
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      echo "Unknown mode: $OMN_MODE" >&2
      usage
      exit 1
      ;;
  esac
}

main "$@"
