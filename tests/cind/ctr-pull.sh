#!/bin/bash

# Retry a command $1 times until it succeeds. Wait $2 seconds between retries.
# (borrowed from OCI runc/tests/integration/helpers.bash)
function retry() {
  local attempts=$1
  shift
  local delay=$1
  shift
  local i

  for ((i = 0; i < attempts; i++)); do
    $@ > /dev/null 2>&1
    if [ "$?" -eq 0 ]; then
	return 0
    fi
    sleep $delay
  done

  echo "Command \"$@\" failed $attempts times. Output: $?"
  false
}

# containerd start
containerd > /var/log/containerd.log 2>&1 &
sleep 3
retry 10 1 "ctr -v"

# pull inner images
ctr image pull ghcr.io/nestybox/busybox:latest
ctr image pull ghcr.io/nestybox/alpine:latest
