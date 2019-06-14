#!/usr/bin/env bats

#
# Bats command execution wrappers
#
# Note: assumes the setup helper is loaded
#

# Wrapper for sysvisor-runc using bats
function runc() {
  run __runc "$@"

  # Some debug information to make life easier. bats will only print it if the
  # test failed, in which case the output is useful.
  echo "runc $@ (status=$status):" >&2
  echo "$output" >&2
}

# Wrapper for docker using bats
function docker() {
  run __docker "$@"
  echo "docker $@ (status=$status):" >&2
  echo "$output"
}

# Need this to avoid recursion on docker function
function __docker() {
  command docker "$@"
}

# Run a background process
function bats_background() {
  # To prevent background processes from hanging bats, we need to
  # close FD 3; see https://github.com/sstephenson/bats/issues/80#issuecomment-174101686
  "$@" 3>/dev/null &
}

function sysvisor_mgr_start() {
  # Note: must match the way sysvisor-mgr is usually started, except
  # that we also pass in the "$@".
  bats_background sysvisor-mgr --log /dev/stdout "$@" > /var/log/sysvisor-mgr.log 2>&1
}

function sysvisor_mgr_stop() {
  pid=$(pidof sysvisor-mgr)
  kill $pid
}
