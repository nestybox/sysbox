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

# Waits for systemd to initialize inside a container
function wait_for_systemd_init() {
	local syscont=$1

	#
	# For systemd to be deemed as fully initialized, we must have at least
	# these four processes running.
	#
	# admin@sys-cont:~$ ps -ef | grep systemd
	# root       273     1  0 Oct22 ?        00:00:00 /lib/systemd/systemd-journald
	# systemd+   481     1  0 Oct22 ?        00:00:00 /lib/systemd/systemd-resolved
	# message+   844     1  0 Oct22 ?        00:00:00 /usr/bin/dbus-daemon --system --systemd-activation
	# root       871     1  0 Oct22 ?        00:00:00 /lib/systemd/systemd-logind
	#

	# XXX: For some reason the following retry is not working under
	# bats, which complains with "BATS_ERROR_STACK_TRACE: bad array
	# subscript" every so often. It's related to the pipe into grep.
	# As a work-around, we just wait for a few seconds for Systemd to
	# initialize.

	#retry 10 1 __docker exec "$syscont" \
		#    sh -c "ps -ef | egrep systemd | wc -l | egrep [4-9]+"

	sleep 40
}

# Waits for systemd to boot inside a system container
function wait_for_inner_systemd {
  local syscont=$1

  retry_run 10 1 "__docker exec $syscont systemctl is-system-running --wait"

  docker exec $syscont sh -c "systemctl is-system-running | grep -q running"
  [ "$status" -eq 0 ]
}
