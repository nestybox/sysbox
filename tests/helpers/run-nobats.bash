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

# Wrapper for sysbox-runc
function sv_runc() {
  __sv_runc "$@"
}

function docker_run() {
  docker run --runtime=sysbox-runc -d "$@"
}

function docker_stop() {
  [[ "$#" == 1 ]]

  id="$1"
  if [ -z "$id" ]; then
    return 0
  fi

  docker stop -t0 "$id"
}

function sv_mgr_start() {
  # Note: must match the way sysbox-mgr is usually started, except
  # that we also pass in the "$@".
  sysbox-mgr --log /dev/stdout "$@" > /var/log/sysbox-mgr.log 2>&1 &
  sleep 1
}

function sv_mgr_stop() {
  pid=$(pidof sysbox-mgr)
  kill $pid
}

function dockerd_start() {
  dockerd "$@" > /var/log/dockerd.log 2>&1 &
  sleep 2
}

function dockerd_stop() {
  pid=$(pidof dockerd)
  kill $pid
  if [ -f /var/run/docker.pid ]; then rm /var/run/docker.pid; fi
}
