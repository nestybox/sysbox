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

# dockerd start
dockerd > /var/log/dockerd.log 2>&1 &
retry 10 1 "docker ps"

# pull inner images
docker pull busybox:latest
docker pull alpine:latest

# dockerd cleanup (remove the .pid file as otherwise it prevents
# dockerd from launching correctly inside sys container)
kill $(cat /var/run/docker.pid)
kill $(cat /run/docker/containerd/containerd.pid)
rm -f /var/run/docker.pid
rm -f /run/docker/containerd/containerd.pid
