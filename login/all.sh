#!/usr/bin/env bash

run_login() {
  run_logged "$OMN_PATH/login/sddm.sh"
  run_logged "$OMN_PATH/login/limine.sh"
}
