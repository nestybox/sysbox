#!/usr/bin/env bats

#
# Basic security checks
#

load ../helpers/run
load ../helpers/docker
load ../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

@test "sysbox-fs nsenter mount leak" {

	# Note: test steps based on a security report by Gabriel Diener @ Klarna.com.

	local syscont=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)

	# From inside container, perform an action that triggers sysbox-fs to dispatch
	# a process that enters the container namespaces (aka nsenter process)
	docker exec -d "$syscont" bash -c "while :; do find /sys/devices/virtual; done >/dev/null 2>&1 &"
	[ "$status" -eq 0 ]

	docker exec -d "$syscont" bash -c "while ! ps awwwfux | egrep -B1 '[[:digit:]] /usr/bin/sysbox-fs'; do :; done"
	[ "$status" -eq 0 ]

	# Pause the sysbox-fs nsenter process
	docker exec "$syscont" bash -c "while ! pkill -STOP runc:; do :; done; echo Stopped"
	[ "$status" -eq 0 ]

	# Get the nsenter process mounts.
	docker exec "$syscont" bash -c "cat /proc/\$(pgrep runc: | head -n 1)/mounts"
	[ "$status" -eq 0 ]
	local nsenter_mounts=$output

	# Compare the host (i.e., the test suite container) and nsenter process
	# overlay mounts. The host is expected to have >=2 overlay mounts, one for
	# the test suite container's root and another for each sysbox
	# container. However the nsenter process should see a single overlay mount
	# (that of the sysbox container's root). If the nsenter process sees > 1
	# overlay mount, host mounts must have been leaked.
	local host_overlay_mounts=$(cat /proc/self/mounts | grep -c "^overlay ")
	local nsenter_overlay_mounts=$(echo "$nsenter_mounts" | grep -c "^overlay ")

	echo "host_overlay_mounts = $host_overlay_mounts"
	echo "nsenter_overlay_mounts = $nsenter_overlay_mounts"

	[ $host_overlay_mounts -ge 2 ]
	[ $nsenter_overlay_mounts -eq 1 ]

	docker_stop "$syscont"
}
