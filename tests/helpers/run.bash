#!/usr/bin/env bats

#
# Bats run wrappers
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
