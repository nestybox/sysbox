#!/bin/bash

#
# Command execution wrappers (without bats)
#
# These are useful for manually reproducing failures step-by-step by cut & pasting
# test steps into the test container's shell.
#
# Note: assumes the setup helper is loaded
#

# Wrapper for sysvisor-runc
function runc() {
  __runc "$@"
}

# Wrapper for docker using bats
function docker() {
  __docker "$@"
}

# Need this to avoid recursion on docker function
function __docker() {
  command docker "$@"
}

function sysvisor_mgr_start() {
  # Note: must match the way sysvisor-mgr is usually started, except
  # that we also pass in the "$@".
  sysvisor-mgr --log /dev/stdout "$@" > /var/log/sysvisor-mgr.log 2>&1
}

function sysvisor_mgr_stop() {
  pid=$(pidof sysvisor-mgr)
  kill $pid
}
