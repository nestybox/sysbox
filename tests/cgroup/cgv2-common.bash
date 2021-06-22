#!/bin/bash

#
# Test functions for cgroups v2
#

function test_cgroup_cpuset() {

	if [ $(nproc) -lt 2 ]; then
		skip "skip (requires host with > 2 processors)"
	fi

	# Run a container and constrain it to cpus [0,1]
	local syscont=$(docker_run --rm --cpuset-cpus="0-1" ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

	#
	# Verify cgroup config looks good at host-level
	#
	local cgPathHost=$(get_docker_cgroupv2_path $syscont)
	local cgControllers=$(get_docker_cgroupv2_controllers)
	local pid=$(docker_cont_pid $syscont)

	echo "cgPathHost = $cgPathHost"

	run cat "${cgPathHost}/cpuset.cpus"
	[ "$status" -eq 0 ]
	[[ "$output" == "0-1" ]]

	run cat "${cgPathHost}/cgroup.procs"
	[ "$status" -eq 0 ]
	[[ "$output" == "" ]]

	run cat "${cgPathHost}/cgroup.type"
	[ "$status" -eq 0 ]
	[[ "$output" == "domain" ]]

	run cat "${cgPathHost}/cgroup.controllers"
	[ "$status" -eq 0 ]
	[[ "$output" == "$cgControllers" ]]

	run cat "${cgPathHost}/${SYSCONT_CGROUP_INIT}/cgroup.procs"
	[ "$status" -eq 0 ]
	[[ "$output" == "$pid" ]]

	#
	# Verify cgroup config looks good inside the container and delegation works
	#
	local cgPathCont="/sys/fs/cgroup/"
	local cgPathContInit="${cgPathCont}/init.scope"

	docker exec "$syscont" sh -c "cat ${cgPathCont}/cpuset.cpus"
	[ "$status" -eq 0 ]
	[[ "$output" == "0-1" ]]

	docker exec "$syscont" sh -c "cat ${cgPathContInit}/cgroup.procs"
	[ "$status" -eq 0 ]
	[ "${lines[0]}" -eq 1 ]

	docker exec "$syscont" sh -c "echo \"0-3\" > ${cgPathCont}/cpuset.cpus"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Permission denied" ]]

	docker exec "$syscont" sh -c "echo \"0-3\" > ${cgPathContInit}/cpuset.cpus"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Permission denied" ]]

	docker exec "$syscont" sh -c "mkdir ${cgPathCont}/test"
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c "cat ${cgPathCont}/test/cgroup.type"
	[ "$status" -eq 0 ]
	[[ "$output" == "domain" ]]

	docker exec "$syscont" sh -c "echo 1 > ${cgPathCont}/test/cpuset.cpus"
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c "cat ${cgPathCont}/test/cpuset.cpus"
	[ "$status" -eq 0 ]
	[[ "$output" == "1" ]]

	# stop the container
	docker_stop "$syscont"

	# verify cgroup dir was cleaned up on host
	[ ! -d "$cgPathHost" ]
}

function test_cgroup_cpus() {

	# Run a container and give it 10% cpu bandwidth
	local syscont=$(docker_run --rm --cpus="0.1" ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

	#
	# Verify cgroup config looks good at host-level
	#
	local cgPathHost=$(get_docker_cgroupv2_path $syscont)
	local cgControllers=$(get_docker_cgroupv2_controllers)
	local pid=$(docker_cont_pid $syscont)

	run cat "${cgPathHost}/cpu.max"
	[ "$status" -eq 0 ]
	[[ "$output" == "10000 100000" ]]

	run cat "${cgPathHost}/cgroup.procs"
	[ "$status" -eq 0 ]
	[[ "$output" == "" ]]

	run cat "${cgPathHost}/cgroup.type"
	[ "$status" -eq 0 ]
	[[ "$output" == "domain" ]]

	run cat "${cgPathHost}/cgroup.controllers"
	[ "$status" -eq 0 ]
	[[ "$output" == "$cgControllers" ]]

	run cat "${cgPathHost}/${SYSCONT_CGROUP_INIT}/cgroup.procs"
	[ "$status" -eq 0 ]
	[[ "$output" == "$pid" ]]

	#
	# Verify cgroup config looks good inside the container and delegation works
	#
	local cgPathCont="/sys/fs/cgroup/"
	local cgPathContInit="${cgPathCont}/init.scope"

	docker exec "$syscont" sh -c "cat ${cgPathCont}/cpu.max"
	[ "$status" -eq 0 ]
	[[ "$output" == "10000 100000" ]]

	docker exec "$syscont" sh -c "cat ${cgPathContInit}/cpu.max"
	[ "$status" -eq 0 ]
	[[ "$output" == "max 100000" ]]

	docker exec "$syscont" sh -c "cat ${cgPathContInit}/cgroup.procs"
	[ "$status" -eq 0 ]
	[ "${lines[0]}" -eq 1 ]

	docker exec "$syscont" sh -c "mkdir ${cgPathCont}/test"
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c "cat ${cgPathCont}/test/cgroup.type"
	[ "$status" -eq 0 ]
	[[ "$output" == "domain" ]]

	docker exec "$syscont" sh -c "cat ${cgPathCont}/test/cpu.max"
	[ "$status" -eq 0 ]
	[[ "$output" == "max 100000" ]]

	# stop the container
	docker_stop "$syscont"

	# verify cgroup dir was cleaned up on host
	[ ! -d "$cgPathHost" ]
}

#
# TODO: Modify this test for cgroups v2...
#
function test_cgroup_memory() {

	# Run a container and give it a max RAM of 16M
	local syscont=$(docker_run --rm --memory="16M" ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

	#
	# Verify cgroup config looks good at host-level
	#
	local cgPathHost=$(get_docker_cgroupv2_path $syscont)
	local cgControllers=$(get_docker_cgroupv2_controllers)
	local pid=$(docker_cont_pid $syscont)

	run cat "${cgPathHost}/memory.max"
	[ "$status" -eq 0 ]
	[[ "$output" == "16777216" ]]

	run cat "${cgPathHost}/cgroup.procs"
	[ "$status" -eq 0 ]
	[[ "$output" == "" ]]

	# The mem limit is not visible in the child cgroup, though it's enforced
	run cat "${cgPathHost}/${SYSCONT_CGROUP_INIT}/memory.max"
	[ "$status" -eq 0 ]
	[[ "$output" == "max" ]]

	run cat "${cgPathHost}/${SYSCONT_CGROUP_INIT}/cgroup.procs"
	[ "$status" -eq 0 ]
	[[ "$output" == "$pid" ]]

	#
	# Verify cgroup config looks good inside the container and delegation works
	#
	local cgPathCont="/sys/fs/cgroup"
	local cgPathContInit="${cgPathCont}/init.scope"

	docker exec "$syscont" sh -c "cat ${cgPathCont}/memory.max"
	[ "$status" -eq 0 ]
	[[ "$output" == "16777216" ]]

	docker exec "$syscont" sh -c "cat ${cgPathCont}/cgroup.procs"
	[ "$status" -eq 0 ]
	[[ "$output" == "" ]]

	docker exec "$syscont" sh -c "cat ${cgPathContInit}/cgroup.procs"
	[ "$status" -eq 0 ]
	[ "${lines[0]}" -eq 1 ]

	# stop the container
	docker_stop "$syscont"

	# verify cgroup dir was cleaned up on host
	[ ! -d "$cgPathHost" ]
}

function test_cgroup_perm() {

	local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

	#
	# Verify /sys/fs/cgroup permissions look good inside the container
	#
	local cgPathCont="/sys/fs/cgroup/"
	local cgPathContInit="${cgPathCont}/init.scope"

	# Delegation boundary
	docker exec "$syscont" sh -c "ls -lL ${cgPathCont} | tail -n +2"
	[ "$status" -eq 0 ]

	for line in "${lines[@]}"; do
		local name=$(echo $line | awk '{print $9}')
		if [[ "$name" == "cgroup.procs" ]] ||
			[[ "$name" == "cgroup.subtree_control" ]] ||
			[[ "$name" == "cgroup.threads" ]] ||
			[[ "$name" == "$SYSCONT_CGROUP_INIT" ]]; then
			verify_owner "root" "root" $line
		else
			verify_owner "nobody" "nobody" $line
		fi
	done

	# sys container init cgroup (created by sysbox)
	docker exec "$syscont" sh -c "ls -lL ${cgPathContInit} | tail -n +2"
	[ "$status" -eq 0 ]

	for line in "${lines[@]}"; do
		local name=$(echo $line | awk '{print $9}')
		if [[ "$name" == "cgroup.procs" ]] ||
			[[ "$name" == "cgroup.subtree_control" ]] ||
			[[ "$name" == "cgroup.threads" ]] ||
			[[ "$name" == "$SYSCONT_CGROUP_INIT" ]]; then
			verify_owner "root" "root" $line
		else
			verify_owner "nobody" "nobody" $line
		fi
	done

	# Inner cgroup
	docker exec "$syscont" sh -c "mkdir ${cgPathCont}/test"
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c "ls -lL ${cgPathCont}/test | tail -n +2"
	[ "$status" -eq 0 ]

	for line in "${lines[@]}"; do
		verify_owner "root" "root" $line
	done

	docker exec "$syscont" sh -c "rmdir ${cgPathCont}/test"
	[ "$status" -eq 0 ]

	#
	# Verify cgroup permissions look good at host-level
	#
	local cgPathHost=$(get_docker_cgroupv2_path $syscont)
	local uid=$(docker_root_uid_map $syscont)
	local gid=$(docker_root_gid_map $syscont)

	# Verify cgroup for sys container is owned by root:root at host level, except
	# for delegation files.
	run sh -c "ls -lL $cgPathHost | tail -n +2"
	[ "$status" -eq 0 ]

	for line in "${lines[@]}"; do
		local name=$(echo $line | awk '{print $9}')
		if [[ "$name" == "cgroup.procs" ]] ||
			[[ "$name" == "cgroup.subtree_control" ]] ||
			[[ "$name" == "cgroup.threads" ]] ||
			[[ "$name" == "$SYSCONT_CGROUP_INIT" ]]; then
			verify_owner "$uid" "$gid" $line
		else
			verify_owner "root" "root" $line
		fi
	done

	docker_stop "$syscont"
}

function test_cgroup_delegation() {

	#
	# Verify cgroup delegation works (e.g., systemd-in-docker can assign cgroups without problem).
	#

	# Launch sys container with systemd
	local syscont=$(docker_run --rm  ${CTR_IMG_REPO}/ubuntu-focal-systemd-docker)

	sleep 15

	# Verify that systemd has been properly initialized (no major errors observed).
	docker exec "$syscont" sh -c "systemctl status"
	[ "$status" -eq 0 ]
	[[ "${lines[1]}" =~ "State: running" ]]

	# check that systemd has assigned cgroups properly inside the container (e.g,
	# for the docker service).
   docker exec "$syscont" sh -c "pidof dockerd"
	[ "$status" -eq 0 ]
	inner_docker_pid="$output"

	docker exec "$syscont" sh -c "cat /sys/fs/cgroup/system.slice/docker.service/cgroup.procs"
	[ "$status" -eq 0 ]
	[[ "$output" == "$inner_docker_pid" ]]

	docker_stop "$syscont"
}
