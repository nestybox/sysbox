#!/usr/bin/env bats

#
# Systemd Test Helper Functions
#

load $(dirname ${BASH_SOURCE[0]})/run.bash

# Indicates if systemd is pid 1 in the test container
function systemd_env() {
	ret=$(readlink /proc/1/exe)
	if [[ "$ret" =~ "/lib/systemd/systemd" ]]; then
		return 0
	else
		return 1
	fi
}

# Waits for systemd to boot inside a system container
function wait_for_inner_systemd {
  local syscont=$1

  retry_run 10 1 "__docker exec $syscont systemctl is-system-running --wait"

  docker exec $syscont sh -c "systemctl is-system-running | grep -q running"
  [ "$status" -eq 0 ]
}
