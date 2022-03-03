#!/usr/bin/env bats

#
# Verify the Sysbox "honor-caps" config
#

load ../helpers/run
load ../helpers/docker
load ../helpers/sysbox
load ../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

@test "default caps" {

	# Root user process starts with all caps enabled
	run __docker run --runtime=sysbox-runc --rm ${CTR_IMG_REPO}/alpine sh -c "cat /proc/self/status | grep -i cap"
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" =~ "CapInh:".+"0000003fffffffff" ]]
	[[ "${lines[1]}" =~ "CapPrm:".+"0000003fffffffff" ]]
	[[ "${lines[2]}" =~ "CapEff:".+"0000003fffffffff" ]]
	[[ "${lines[3]}" =~ "CapBnd:".+"0000003fffffffff" ]]
	[[ "${lines[4]}" =~ "CapAmb:".+"0000003fffffffff" ]]

	# Non-root user process starts with all caps disabled
	run __docker run --runtime=sysbox-runc -u 1000:1000 --rm ${CTR_IMG_REPO}/alpine sh -c "cat /proc/self/status | grep -i cap"
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" =~ "CapInh:".+"0000000000000000" ]]
	[[ "${lines[1]}" =~ "CapPrm:".+"0000000000000000" ]]
	[[ "${lines[2]}" =~ "CapEff:".+"0000000000000000" ]]
	[[ "${lines[3]}" =~ "CapBnd:".+"0000003fffffffff" ]]
	[[ "${lines[4]}" =~ "CapAmb:".+"0000000000000000" ]]

	# Verify exec into container behaves the same
	local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine tail -f /dev/null)
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c "cat /proc/self/status | grep -i cap"
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" =~ "CapInh:".+"0000003fffffffff" ]]
	[[ "${lines[1]}" =~ "CapPrm:".+"0000003fffffffff" ]]
	[[ "${lines[2]}" =~ "CapEff:".+"0000003fffffffff" ]]
	[[ "${lines[3]}" =~ "CapBnd:".+"0000003fffffffff" ]]
	[[ "${lines[4]}" =~ "CapAmb:".+"0000003fffffffff" ]]

	docker exec -u 1000:1000 "$syscont" sh -c "cat /proc/self/status | grep -i cap"
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" =~ "CapInh:".+"0000000000000000" ]]
	[[ "${lines[1]}" =~ "CapPrm:".+"0000000000000000" ]]
	[[ "${lines[2]}" =~ "CapEff:".+"0000000000000000" ]]
	[[ "${lines[3]}" =~ "CapBnd:".+"0000003fffffffff" ]]
	[[ "${lines[4]}" =~ "CapAmb:".+"0000000000000000" ]]

	docker_stop $syscont
}

@test "honor caps envvar" {

	# Honor caps for root user process
	run __docker run --runtime=sysbox-runc -e "SYSBOX_HONOR_CAPS=TRUE" --rm ${CTR_IMG_REPO}/alpine sh -c "cat /proc/self/status | grep -i cap"
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" =~ "CapInh:".+"00000000a80425fb" ]]
	[[ "${lines[1]}" =~ "CapPrm:".+"00000000a80425fb" ]]
	[[ "${lines[2]}" =~ "CapEff:".+"00000000a80425fb" ]]
	[[ "${lines[3]}" =~ "CapBnd:".+"00000000a80425fb" ]]
	[[ "${lines[4]}" =~ "CapAmb:".+"0000000000000000" ]]
	local sysbox_root_caps="$output"

	# Honor caps for non root user process
	run __docker run --runtime=sysbox-runc -e "SYSBOX_HONOR_CAPS=TRUE" -u 1000:1000 --rm ${CTR_IMG_REPO}/alpine sh -c "cat /proc/self/status | grep -i cap"
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" =~ "CapInh:".+"00000000a80425fb" ]]
	[[ "${lines[1]}" =~ "CapPrm:".+"0000000000000000" ]]
	[[ "${lines[2]}" =~ "CapEff:".+"0000000000000000" ]]
	[[ "${lines[3]}" =~ "CapBnd:".+"00000000a80425fb" ]]
	[[ "${lines[4]}" =~ "CapAmb:".+"0000000000000000" ]]
	local sysbox_non_root_caps="$output"

	# Verify sysbox with "honor caps" matches the OCI runc caps
	run __docker run --runtime=runc --rm ${CTR_IMG_REPO}/alpine sh -c "cat /proc/self/status | grep -i cap"
	[ "$status" -eq 0 ]
	local runc_root_caps="$output"

	run __docker run --runtime=runc -u 1000:1000 --rm ${CTR_IMG_REPO}/alpine sh -c "cat /proc/self/status | grep -i cap"
	[ "$status" -eq 0 ]
	local runc_non_root_caps="$output"

	[[ "$sysbox_root_caps" == "$runc_root_caps" ]]
	[[ "$sysbox_non_root_caps" == "$runc_non_root_caps" ]]

	# Verify exec into container behaves the same
	local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine tail -f /dev/null)
	[ "$status" -eq 0 ]

	docker exec -e "SYSBOX_HONOR_CAPS=TRUE" "$syscont" sh -c "cat /proc/self/status | grep -i cap"
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" =~ "CapInh:".+"00000000a80425fb" ]]
	[[ "${lines[1]}" =~ "CapPrm:".+"00000000a80425fb" ]]
	[[ "${lines[2]}" =~ "CapEff:".+"00000000a80425fb" ]]
	[[ "${lines[3]}" =~ "CapBnd:".+"00000000a80425fb" ]]
	[[ "${lines[4]}" =~ "CapAmb:".+"0000000000000000" ]]

	docker exec -e "SYSBOX_HONOR_CAPS=TRUE" -u 1000:1000 "$syscont" sh -c "cat /proc/self/status | grep -i cap"
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" =~ "CapInh:".+"00000000a80425fb" ]]
	[[ "${lines[1]}" =~ "CapPrm:".+"0000000000000000" ]]
	[[ "${lines[2]}" =~ "CapEff:".+"0000000000000000" ]]
	[[ "${lines[3]}" =~ "CapBnd:".+"00000000a80425fb" ]]
	[[ "${lines[4]}" =~ "CapAmb:".+"0000000000000000" ]]

	docker_stop $syscont
}

@test "cap add/drop" {

	# By default, cap add/drop is ignored

	run __docker run --runtime=sysbox-runc --rm --cap-drop=ALL ${CTR_IMG_REPO}/alpine sh -c "cat /proc/self/status | grep -i cap"
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" =~ "CapInh:".+"0000003fffffffff" ]]
	[[ "${lines[1]}" =~ "CapPrm:".+"0000003fffffffff" ]]
	[[ "${lines[2]}" =~ "CapEff:".+"0000003fffffffff" ]]
	[[ "${lines[3]}" =~ "CapBnd:".+"0000003fffffffff" ]]
	[[ "${lines[4]}" =~ "CapAmb:".+"0000003fffffffff" ]]

	run __docker run --runtime=sysbox-runc --rm -u 1000:1000 --cap-add=ALL ${CTR_IMG_REPO}/alpine sh -c "cat /proc/self/status | grep -i cap"
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" =~ "CapInh:".+"0000000000000000" ]]
	[[ "${lines[1]}" =~ "CapPrm:".+"0000000000000000" ]]
	[[ "${lines[2]}" =~ "CapEff:".+"0000000000000000" ]]
	[[ "${lines[3]}" =~ "CapBnd:".+"0000003fffffffff" ]]
	[[ "${lines[4]}" =~ "CapAmb:".+"0000000000000000" ]]


	# If we honor caps, then cap add/drop is honored
	run __docker run --runtime=sysbox-runc --rm -e "SYSBOX_HONOR_CAPS=TRUE" --cap-drop=ALL --cap-add=SYS_ADMIN ${CTR_IMG_REPO}/alpine sh -c "cat /proc/self/status | grep -i cap"
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" =~ "CapInh:".+"0000000000200000" ]]
	[[ "${lines[1]}" =~ "CapPrm:".+"0000000000200000" ]]
	[[ "${lines[2]}" =~ "CapEff:".+"0000000000200000" ]]
	[[ "${lines[3]}" =~ "CapBnd:".+"0000000000200000" ]]
	[[ "${lines[4]}" =~ "CapAmb:".+"0000000000000000" ]]
	local sysbox_root_caps="$output"

	run __docker run --runtime=sysbox-runc --rm -e "SYSBOX_HONOR_CAPS=TRUE" -u 1000:1000 --cap-add=ALL ${CTR_IMG_REPO}/alpine sh -c "cat /proc/self/status | grep -i cap"
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" =~ "CapInh:".+"0000003fffffffff" ]]
	[[ "${lines[1]}" =~ "CapPrm:".+"0000000000000000" ]]
	[[ "${lines[2]}" =~ "CapEff:".+"0000000000000000" ]]
	[[ "${lines[3]}" =~ "CapBnd:".+"0000003fffffffff" ]]
	[[ "${lines[4]}" =~ "CapAmb:".+"0000000000000000" ]]
	local sysbox_non_root_caps="$output"

	run __docker run --runtime=runc --rm --cap-drop=ALL --cap-add=SYS_ADMIN ${CTR_IMG_REPO}/alpine sh -c "cat /proc/self/status | grep -i cap"
	[ "$status" -eq 0 ]
	local runc_root_caps="$output"

	run __docker run --runtime=runc --rm -u 1000:1000 --cap-add=ALL ${CTR_IMG_REPO}/alpine sh -c "cat /proc/self/status | grep -i cap"
	[ "$status" -eq 0 ]
	local runc_non_root_caps="$output"

	[[ "$sysbox_root_caps" == "$runc_root_caps" ]]
	[[ "$sysbox_non_root_caps" == "$runc_non_root_caps" ]]
}

@test "honor caps global config" {

	sysbox_stop
   sysbox_start --honor-caps

	# Honor caps for root user process
	run __docker run --runtime=sysbox-runc --rm ${CTR_IMG_REPO}/alpine sh -c "cat /proc/self/status | grep -i cap"
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" =~ "CapInh:".+"00000000a80425fb" ]]
	[[ "${lines[1]}" =~ "CapPrm:".+"00000000a80425fb" ]]
	[[ "${lines[2]}" =~ "CapEff:".+"00000000a80425fb" ]]
	[[ "${lines[3]}" =~ "CapBnd:".+"00000000a80425fb" ]]
	[[ "${lines[4]}" =~ "CapAmb:".+"0000000000000000" ]]
	local sysbox_root_caps="$output"

	# Honor caps for non root user process
	run __docker run --runtime=sysbox-runc -u 1000:1000 --rm ${CTR_IMG_REPO}/alpine sh -c "cat /proc/self/status | grep -i cap"
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" =~ "CapInh:".+"00000000a80425fb" ]]
	[[ "${lines[1]}" =~ "CapPrm:".+"0000000000000000" ]]
	[[ "${lines[2]}" =~ "CapEff:".+"0000000000000000" ]]
	[[ "${lines[3]}" =~ "CapBnd:".+"00000000a80425fb" ]]
	[[ "${lines[4]}" =~ "CapAmb:".+"0000000000000000" ]]
	local sysbox_non_root_caps="$output"

	# Verify sysbox with "honor caps" matches the OCI runc caps
	run __docker run --runtime=runc --rm ${CTR_IMG_REPO}/alpine sh -c "cat /proc/self/status | grep -i cap"
	[ "$status" -eq 0 ]
	local runc_root_caps="$output"

	run __docker run --runtime=runc -u 1000:1000 --rm ${CTR_IMG_REPO}/alpine sh -c "cat /proc/self/status | grep -i cap"
	[ "$status" -eq 0 ]
	local runc_non_root_caps="$output"

	[[ "$sysbox_root_caps" == "$runc_root_caps" ]]
	[[ "$sysbox_non_root_caps" == "$runc_non_root_caps" ]]

	# Verify global config can be overriden by per-container config
	run __docker run --runtime=sysbox-runc -e "SYSBOX_HONOR_CAPS=FALSE" --rm ${CTR_IMG_REPO}/alpine sh -c "cat /proc/self/status | grep -i cap"
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" =~ "CapInh:".+"0000003fffffffff" ]]
	[[ "${lines[1]}" =~ "CapPrm:".+"0000003fffffffff" ]]
	[[ "${lines[2]}" =~ "CapEff:".+"0000003fffffffff" ]]
	[[ "${lines[3]}" =~ "CapBnd:".+"0000003fffffffff" ]]
	[[ "${lines[4]}" =~ "CapAmb:".+"0000003fffffffff" ]]

	run __docker run --runtime=sysbox-runc -e "SYSBOX_HONOR_CAPS=FALSE" -u 1000:1000 --rm ${CTR_IMG_REPO}/alpine sh -c "cat /proc/self/status | grep -i cap"
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" =~ "CapInh:".+"0000000000000000" ]]
	[[ "${lines[1]}" =~ "CapPrm:".+"0000000000000000" ]]
	[[ "${lines[2]}" =~ "CapEff:".+"0000000000000000" ]]
	[[ "${lines[3]}" =~ "CapBnd:".+"0000003fffffffff" ]]
	[[ "${lines[4]}" =~ "CapAmb:".+"0000000000000000" ]]

	# Verify exec into container behaves properly
	local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine tail -f /dev/null)
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c "cat /proc/self/status | grep -i cap"
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" =~ "CapInh:".+"00000000a80425fb" ]]
	[[ "${lines[1]}" =~ "CapPrm:".+"00000000a80425fb" ]]
	[[ "${lines[2]}" =~ "CapEff:".+"00000000a80425fb" ]]
	[[ "${lines[3]}" =~ "CapBnd:".+"00000000a80425fb" ]]
	[[ "${lines[4]}" =~ "CapAmb:".+"0000000000000000" ]]

	docker exec -u 1000:1000 "$syscont" sh -c "cat /proc/self/status | grep -i cap"
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" =~ "CapInh:".+"00000000a80425fb" ]]
	[[ "${lines[1]}" =~ "CapPrm:".+"0000000000000000" ]]
	[[ "${lines[2]}" =~ "CapEff:".+"0000000000000000" ]]
	[[ "${lines[3]}" =~ "CapBnd:".+"00000000a80425fb" ]]
	[[ "${lines[4]}" =~ "CapAmb:".+"0000000000000000" ]]

	docker exec -e "SYSBOX_HONOR_CAPS=FALSE" "$syscont" sh -c "cat /proc/self/status | grep -i cap"
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" =~ "CapInh:".+"0000003fffffffff" ]]
	[[ "${lines[1]}" =~ "CapPrm:".+"0000003fffffffff" ]]
	[[ "${lines[2]}" =~ "CapEff:".+"0000003fffffffff" ]]
	[[ "${lines[3]}" =~ "CapBnd:".+"0000003fffffffff" ]]
	[[ "${lines[4]}" =~ "CapAmb:".+"0000003fffffffff" ]]

	docker exec -e "SYSBOX_HONOR_CAPS=FALSE" -u 1000:1000 "$syscont" sh -c "cat /proc/self/status | grep -i cap"
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" =~ "CapInh:".+"0000000000000000" ]]
	[[ "${lines[1]}" =~ "CapPrm:".+"0000000000000000" ]]
	[[ "${lines[2]}" =~ "CapEff:".+"0000000000000000" ]]
	[[ "${lines[3]}" =~ "CapBnd:".+"0000003fffffffff" ]]
	[[ "${lines[4]}" =~ "CapAmb:".+"0000000000000000" ]]

	docker_stop $syscont

	sysbox_stop
	sysbox_start
}

@test "honorcaps invalid" {

	run __docker run --rm -e "SYSBOX_HONOR_CAPS=BAD_VAL" ${CTR_IMG_REPO}/alpine:latest echo "test"
	[ "$status" -ne 0 ]

	run __docker run --rm -e "SYSBOX_HONOR_CAPS=BAD_VAL=BAD_VAL2" ${CTR_IMG_REPO}/alpine:latest echo "test"
	[ "$status" -ne 0 ]

	run __docker run --rm -e "SYSBOX_HONOR_CAPS=" ${CTR_IMG_REPO}/alpine:latest echo "test"
	[ "$status" -ne 0 ]
}
