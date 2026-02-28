#!/usr/bin/env bash

run_post_install() {
  run_logged "$OMN_PATH/post-install/desktop.sh" "$@"
  if [[ ${1:-} != "-h" && ${1:-} != "--help" ]]; then
    run_logged "$OMN_PATH/post-install/finished.sh"
  fi
}
