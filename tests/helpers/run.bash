#!/usr/bin/env bats

#
# Bats command execution wrappers
#

load $(dirname ${BASH_SOURCE[0]})/setup.bash

# retry wrapper for bats 'run' commands
#
# Note: the command being retried must not be a bats 'run' command (such
# as those in tests/helpers/run.sh).
function retry_run() {
  local attempts=$1
  shift
  local delay=$1
  shift
  local i

  for ((i = 0; i < attempts; i++)); do
    run $@
    if [ "$status" -eq 0 ]; then
      return 0
    fi
    sleep $delay
  done

  echo "Command \"$@\" failed $attempts times. Output: $status"
  false
}

# Run a background process under bats
function bats_bg() {
  # To prevent background processes from hanging bats, we need to
  # close FD 3; see https://github.com/sstephenson/bats/issues/80#issuecomment-174101686
  "$@" 3>/dev/null &
}

# Use as follows:
#
# function setup() {
#    run_only_test "disable_ipv6 lookup"
#    other_setup_actions
# }
run_only_test() {
  if [ "$BATS_TEST_DESCRIPTION" != "$1" ]; then
    skip
  fi
}

# Use as follows:
#
# function setup() {
#    run_only_test_num 2
#    other_setup_actions
# }
run_only_test_num() {
  if [ "$BATS_TEST_NUMBER" -ne "$1" ]; then
    skip
  fi
}
