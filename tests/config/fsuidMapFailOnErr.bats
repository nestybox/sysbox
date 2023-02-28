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

@test "fsuid-map-fail-on-error set" {

	if ! kernel_supports_shiftfs; then
		skip "shiftfs not supported on host."
	fi

	sysbox_stop
	sysbox_start -t --fsuid-map-fail-on-error

	mkdir -p /mnt/scratch/test
	mount -t shiftfs -o mark /mnt/scratch/test /mnt/scratch/test

	# When fsuid-map-fail-on-err is set, bind-mounting a shiftfs mountpoint
	# will fail when Sysbox tries to ID-map-mount on it (because it can't
	# mount shiftfs or use ID-mapped-mounts on it).
	docker run --runtime=sysbox-runc --rm -v /mnt/scratch/test:/mnt/test ${CTR_IMG_REPO}/alpine tail -f /dev/null
	[ "$status" -ne 0 ]

	umount /mnt/scratch/test
	rm -rf /mnt/scratch/test

	sysbox_stop
	sysbox_start -t
}

@test "fsuid-map-fail-on-error unset" {

	if ! kernel_supports_shiftfs; then
		skip "shiftfs not supported on host."
	fi

   sysbox_start -t

	mkdir -p /mnt/scratch/test
	mount -t shiftfs -o mark /mnt/scratch/test /mnt/scratch/test

	# When fsuid-map-fail-on-err is not set (Sysbox's default), bind-mounting a
	# shiftfs mountpoint will fail but Sysbox will ignore the failure and move
	# on. The mount will show up as "nobody:nogroup" inside the container.
	local syscont=$(docker_run --runtime=sysbox-runc --rm -v /mnt/scratch/test:/mnt/test ${CTR_IMG_REPO}/alpine tail -f /dev/null)

	docker exec $syscont sh -c "ls -l /mnt | grep test"
	[ "$status" -eq 0 ]

	verify_owner "nobody" "nobody" "$output"
	docker_stop $syscont

	umount /mnt/scratch/test
	rm -rf /mnt/scratch/test
}
