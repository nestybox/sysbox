#!/usr/bin/env bats

#
# Verify per-container config via SYSBOX_* env vars.
#

load ../helpers/run
load ../helpers/docker
load ../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

@test "sysbox env vars" {

	run __docker run --rm -e "SYSBOX_IGNORE_SYSFS_CHOWN=TRUE" ${CTR_IMG_REPO}/alpine-docker-dbg:latest chown root:root /sys
	[ "$status" -eq 0 ]

	run __docker run --rm -e "SYSBOX_IGNORE_SYSFS_CHOWN=FALSE" ${CTR_IMG_REPO}/alpine-docker-dbg:latest chown root:root /sys
	[ "$status" -ne 0 ]
}

@test "sysbox env vars on exec" {

	local syscont=$(docker_run --rm -e "SYSBOX_IGNORE_SYSFS_CHOWN=TRUE" ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

	# exec sees the effect of the SYSBOX_* env var
	docker exec "$syscont" sh -c "chown root:root /sys"
	[ "$status" -eq 0 ]

	# Modifying SYSBOX_* env vars on exec is ignored (the env var is fixed at container startup time)
	docker exec -e "SYSBOX_IGNORE_SYSFS_CHOWN=FALSE" "$syscont" sh -c "chown root:root /sys"
	[ "$status" -eq 0 ]

   docker_stop "$syscont"

	# Change the value of the env var
	local syscont=$(docker_run --rm -e "SYSBOX_IGNORE_SYSFS_CHOWN=FALSE" ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

	# exec sees the effect of the SYSBOX_* env var
	docker exec "$syscont" sh -c "chown root:root /sys"
	[ "$status" -eq 1 ]

	# Modifying SYSBOX_* env vars on exec is ignored (the env var is fixed at container startup time)
	docker exec -e "SYSBOX_IGNORE_SYSFS_CHOWN=TRUE" "$syscont" sh -c "chown root:root /sys"
	[ "$status" -eq 1 ]

	docker_stop "$syscont"
}

@test "sysbox env vars multi-container" {

	local sc1=$(docker_run --rm -e "SYSBOX_IGNORE_SYSFS_CHOWN=TRUE" ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
	local sc2=$(docker_run --rm -e "SYSBOX_IGNORE_SYSFS_CHOWN=FALSE" ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

	docker exec "$sc1" sh -c "chown root:root /sys"
	[ "$status" -eq 0 ]

	docker exec "$sc2" sh -c "chown root:root /sys"
	[ "$status" -eq 1 ]

	docker_stop "$sc1"
	docker_stop "$sc2"
}

@test "sysbox env vars invalid" {

	run __docker run --rm -e "SYSBOX_IGNORE_SYSFS_CHOWN=BAD_VAL" ${CTR_IMG_REPO}/alpine-docker-dbg:latest echo "test"
	[ "$status" -ne 0 ]

	run __docker run --rm -e "SYSBOX_IGNORE_SYSFS_CHOWN=BAD_VAL=BAD_VAL2" ${CTR_IMG_REPO}/alpine-docker-dbg:latest echo "test"
	[ "$status" -ne 0 ]

	run __docker run --rm -e "SYSBOX_IGNORE_SYSFS_CHOWN=" ${CTR_IMG_REPO}/alpine-docker-dbg:latest echo "test"
	[ "$status" -ne 0 ]
}
