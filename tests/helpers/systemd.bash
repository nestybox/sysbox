#!/bin/bash

#
# Systemd Test Helper Functions
#
# Note: for tests using bats.
#

load ../helpers/run

function systemd_env() {
	ret=$(readlink /proc/1/exe)
	if [[ "$ret" =~ "/usr/lib/systemd/systemd" ]]; then
		return 0
	else
		return 1
	fi
}

function wait_for_inner_systemd {
  local syscont=$1

  retry_run 10 1 "__docker exec $syscont systemctl is-system-running --wait"

  docker exec $syscont sh -c "systemctl is-system-running | grep -q running"
  [ "$status" -eq 0 ]
}
