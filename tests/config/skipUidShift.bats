#!/usr/bin/env bats

#
# Verify SYSBOX_SKIP_UID_SHIFT env var.
#

load ../helpers/run
load ../helpers/docker
load ../helpers/fs
load ../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

@test "skip uid shift basic" {
	local syscont=$(docker_run --rm -e "SYSBOX_SKIP_UID_SHIFT=/etc/resolv.conf" ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

	docker exec "$syscont" sh -c "findmnt | grep \"/etc/resolv.conf\" | egrep \"idmapped|shiftfs\""
	[ "$status" -ne 0 ]

	docker exec "$syscont" sh -c "ls -l /etc/resolv.conf"
	[ "$status" -eq 0 ]
	verify_owner "nobody" "nobody" "$output"

	docker_stop "$syscont"
}

@test "skip uid shift multiple paths" {
	# pass multiple paths to SYSBOX_SKIP_UID_SHIFT
	local syscont=$(docker_run --rm -e "SYSBOX_SKIP_UID_SHIFT=/etc/resolv.conf,/etc/hostname" ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

	docker exec "$syscont" sh -c "findmnt | grep \"/etc/resolv.conf\" | egrep \"idmapped|shiftfs\""
	[ "$status" -ne 0 ]

	docker exec "$syscont" sh -c "findmnt | grep \"/etc/hostname\" | egrep \"idmapped|shiftfs\""
	[ "$status" -ne 0 ]

	docker exec "$syscont" sh -c "ls -l /etc/resolv.conf"
	[ "$status" -eq 0 ]
	verify_owner "nobody" "nobody" "$output"

	docker exec "$syscont" sh -c "ls -l /etc/hostname"
	[ "$status" -eq 0 ]
	verify_owner "nobody" "nobody" "$output"

	docker_stop "$syscont"
}

@test "skip uid shift per-container" {
	local syscont1=$(docker_run --rm -e "SYSBOX_SKIP_UID_SHIFT=/etc/resolv.conf" ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
	local syscont2=$(docker_run --rm -e "SYSBOX_SKIP_UID_SHIFT=/etc/hostname" ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
	local syscont3=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

	# check syscont1
	docker exec "$syscont1" sh -c "findmnt | grep \"/etc/resolv.conf\" | egrep \"idmapped|shiftfs\""
	[ "$status" -ne 0 ]

	docker exec "$syscont1" sh -c "ls -l /etc/resolv.conf"
	[ "$status" -eq 0 ]
	verify_owner "nobody" "nobody" "$output"

	# check syscont2
	docker exec "$syscont2" sh -c "findmnt | grep \"/etc/hostname\" | egrep \"idmapped|shiftfs\""
	[ "$status" -ne 0 ]

	docker exec "$syscont2" sh -c "ls -l /etc/hostname"
	[ "$status" -eq 0 ]
	verify_owner "nobody" "nobody" "$output"

	# check syscont3
	docker exec "$syscont3" sh -c "findmnt | grep \"/etc/resolv.conf\" | egrep \"idmapped|shiftfs\""
	[ "$status" -eq 0 ]

	docker exec "$syscont3" sh -c "ls -l /etc/resolv.conf"
	[ "$status" -eq 0 ]
	verify_owner "root" "root" "$output"

	docker exec "$syscont3" sh -c "findmnt | grep \"/etc/hostname\" | egrep \"idmapped|shiftfs\""
	[ "$status" -eq 0 ]

	docker exec "$syscont3" sh -c "ls -l /etc/hostname"
	[ "$status" -eq 0 ]
	verify_owner "root" "root" "$output"

	docker_stop "$syscont1"
	docker_stop "$syscont2"
	docker_stop "$syscont3"
}
