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
  if [ -n "$SB_INSTALLER" ]; then
    sed -i "s/^ExecStart=\(.*sysbox-mgr.log\).*$/ExecStart=\1 $@/" /lib/systemd/system/sysbox-mgr.service
    systemctl daemon-reload
    systemctl restart sysbox
    sleep 3
  else
    sysbox-mgr --log /dev/stdout $@ > /var/log/sysbox-mgr.log 2>&1 &
    sleep 1
  fi
}

function sv_mgr_stop() {
  if [ -n "$SB_INSTALLER" ]; then
    systemctl stop sysbox
    sleep 1
  else
    pid=$(pidof sysbox-mgr)
    kill $pid
    sleep 1
  fi
}

function dockerd_start() {
  if [ -n "$SB_INSTALLER" ]; then
    systemctl start docker.service
    sleep 2
  else
    dockerd $@ > /var/log/dockerd.log 2>&1 &
    sleep 2
  fi
}

function dockerd_stop() {
  if [ -n "$SB_INSTALLER" ]; then
    systemctl stop docker.service
    sleep 1
  else
    pid=$(pidof dockerd)
    kill $pid
    sleep 1
    if [ -f /var/run/docker.pid ]; then rm /var/run/docker.pid; fi
  fi
}
