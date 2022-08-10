#!/usr/bin/env bats

#
# Verify the Sysbox "fsuid-map-fail-on-error" config
#

load ../helpers/run
load ../helpers/docker
load ../helpers/fs
load ../helpers/uid-shift
load ../helpers/sysbox
load ../helpers/sysbox-health

function setup() {
	if !kernel_supports_idmapped_mnt; then
		skip "requires ID-mapped mounts."
	fi
}

function teardown() {
  sysbox_log_check
}

@test "fsuid-map-fail-on-error=true" {

	sysbox_stop
	sysbox_start -t --fsuid-map-fail-on-error=true

	# When fsuid-map-fail-on-err is set, bind-mounting /var/lib into the container
	# will fail when Sysbox tries to ID-map-mount on it because /var/lib has
	# submounts on filesystems on which ID-mapping are not supported (e.g.,
	# /var/lib/sysboxfs, /var/lib/sysbox/shiftfs, etc.)
	docker run --runtime=sysbox-runc --rm -v /var/lib:/mnt/host-var-lib ${CTR_IMG_REPO}/alpine tail -f /dev/null
	[ "$status" -ne 0 ]

	sysbox_stop
	sysbox_start -t
}

@test "fsuid-map-fail-on-error=false" {

	# When fsuid-map-fail-on-err is not set (Sysbox's default), bind-mounting
	# /var/lib into the container will work but files will show up as
	# nobody:nogroup inside the container. That's because ID-mapped mounts won't
	# be mounted on it because of the /var/lib submounts (see explanation in
	# prior test).

	local syscont=$(docker_run --runtime=sysbox-runc --rm -v /var/lib:/mnt/host-var-lib ${CTR_IMG_REPO}/alpine tail -f /dev/null)

	docker exec $syscont sh -c "ls -l /mnt | grep host-var-lib"
	[ "$status" -eq 0 ]

	verify_owner "nobody" "nobody" "$output"
	docker_stop $syscont
}
