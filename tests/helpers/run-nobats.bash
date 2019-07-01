#!/bin/bash

#
# Command execution wrappers (without bats)
#
# These are useful for manually reproducing failures step-by-step by cut & pasting
# test steps into the test container's shell.
#
# NOTE: Do *not* source this file from the bats tests; the tests
# should source "run.bash" instead.
#

. $(dirname ${BASH_SOURCE[0]})/setup.bash

# Wrapper for sysvisor-runc
function sv_runc() {
  __sv_runc "$@"
}

function docker_run() {
  docker run --runtime=sysvisor-runc --rm -d "$@"
}

function docker_stop() {
  [[ "$#" == 1 ]]

  id="$1"
  if [ -z "$id" ]; then
    return 0
  fi

  docker stop -t 0 "$id"
}

function sv_mgr_start() {
  # Note: must match the way sysvisor-mgr is usually started, except
  # that we also pass in the "$@".
  sysvisor-mgr --log /dev/stdout "$@" > /var/log/sysvisor-mgr.log 2>&1 &
  sleep 1
}

function sv_mgr_stop() {
  pid=$(pidof sysvisor-mgr)
  kill $pid
}
