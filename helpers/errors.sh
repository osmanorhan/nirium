#!/usr/bin/env bash

catch_errors() {
  local code=$?
  printf 'ERROR: nirium installer failed at line %s: %s\n' "$LINENO" "${BASH_COMMAND:-unknown}" >&2
  printf 'ERROR: see log: %s\n' "$OMN_LOG_FILE" >&2
  exit "$code"
}
