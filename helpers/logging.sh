#!/usr/bin/env bash

start_install_log() {
  if ! touch "$OMN_LOG_FILE" 2>/dev/null; then
    OMN_LOG_FILE="${OMN_PATH}/install.log"
    touch "$OMN_LOG_FILE" 2>/dev/null || OMN_LOG_FILE="/tmp/nirium.log"
    touch "$OMN_LOG_FILE" 2>/dev/null || true
  fi
  chmod 0644 "$OMN_LOG_FILE" 2>/dev/null || true
  log "nirium installer log: $OMN_LOG_FILE"
}

run_logged() {
  local script="$1"
  shift || true

  log "Running: $(basename "$script")"
  printf '[%s] START %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$script" >>"$OMN_LOG_FILE"
  bash "$script" "$@" 2>&1 | tee -a "$OMN_LOG_FILE"
  local rc=${PIPESTATUS[0]}
  if (( rc == 0 )); then
    printf '[%s] DONE  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$script" >>"$OMN_LOG_FILE"
  else
    printf '[%s] FAIL  %s (code=%s)\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$script" "$rc" >>"$OMN_LOG_FILE"
    return "$rc"
  fi
}
