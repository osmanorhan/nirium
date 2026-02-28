#!/usr/bin/env bash

SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd -P)"
NIRIUM_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
TARGET_STAGE="$NIRIUM_ROOT/stages/2-desktop.sh"

if [[ ! -f $TARGET_STAGE ]]; then
  echo "ERROR: missing stage script: $TARGET_STAGE" >&2
  exit 1
fi

exec bash "$TARGET_STAGE" "$@"
