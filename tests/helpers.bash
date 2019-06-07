#!/bin/bash

SYSCONT_NAME=""

function setup_syscont() {
  run docker run --runtime=sysvisor-runc --rm -d --hostname syscont nestybox/sys-container:debian-plus-docker tail -f /dev/null
  [ "$status" -eq 0 ]

  run docker ps --format "{{.ID}}" | tail -1
  [ "$status" -eq 0 ]
  SYSCONT_NAME="$output"
}

function teardown_syscont() {
  # use '-t 0' to force stop immediately; otherwise it takes several seconds ...
  run docker stop -t 0 "$SYSCONT_NAME"
  [ "$status" -eq 0 ]
}

# Retry a command $1 times until it succeeds. Wait $2 seconds between retries.
# (copied from runc/tests/integration/helpers.bash)
function retry() {
  local attempts=$1
  shift
  local delay=$1
  shift
  local i

  for ((i = 0; i < attempts; i++)); do
    run "$@"
    if [[ "$status" -eq 0 ]]; then
	return 0
    fi
    sleep $delay
  done

  echo "Command \"$@\" failed $attempts times. Output: $output"
  false
}
