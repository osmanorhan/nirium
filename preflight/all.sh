#!/usr/bin/env bash

run_preflight() {
  run_logged "$OMN_PATH/preflight/begin.sh"
  run_logged "$OMN_PATH/preflight/guard.sh"
  run_logged "$OMN_PATH/preflight/show-env.sh"
}
