#!/usr/bin/env bats

#
# Bats command execution wrappers
#

. $(dirname ${BASH_SOURCE[0]})/setup.bash

# Wrapper for sysvisor-runc using bats
function sv_runc() {
  run __sv_runc "$@"

  # Some debug information to make life easier. bats will only print it if the
  # test failed, in which case the output is useful.
  echo "sysvisor-runc $@ (status=$status):" >&2
  echo "$output" >&2
}

# Wrapper for docker using bats
function docker() {
  run __docker "$@"
  echo "docker $@ (status=$status):" >&2
  echo "$output"
}

# Need this to avoid recursion on docker()
function __docker() {
  command docker "$@"
}

# Run a background process under bats
function bats_bg() {
  # To prevent background processes from hanging bats, we need to
  # close FD 3; see https://github.com/sstephenson/bats/issues/80#issuecomment-174101686
  "$@" 3>/dev/null &
}

function sv_mgr_start() {
  # Note: must match the way sysvisor-mgr is usually started, except
  # that we also pass in the "$@".
  bats_bg sysvisor-mgr --log /dev/stdout "$@" > /var/log/sysvisor-mgr.log 2>&1
}

function sv_mgr_stop() {
  pid=$(pidof sysvisor-mgr)
  kill $pid
}
