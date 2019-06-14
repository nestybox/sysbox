#!/bin/bash

#
# Command execution wrappers (without bats)
#
# These are useful for manually reproducing failures step-by-step by cut & pasting
# test steps into the test container's shell.
#

. $(dirname ${BASH_SOURCE[0]})/setup.bash

# Wrapper for sysvisor-runc
function sv_runc() {
  __sv_runc "$@"
}

function sv_mgr_start() {
  # Note: must match the way sysvisor-mgr is usually started, except
  # that we also pass in the "$@".
  sysvisor-mgr --log /dev/stdout "$@" > /var/log/sysvisor-mgr.log 2>&1
}

function sv_mgr_stop() {
  pid=$(pidof sysvisor-mgr)
  kill $pid
}
