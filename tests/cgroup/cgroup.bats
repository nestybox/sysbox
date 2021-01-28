#!/usr/bin/env bats

#
# Tests that verify cgroup contraints and delegation on system containers.
#
# The tests verify that a sys container is limited by the cgroups assigned to it
# at creation time, and these limits can't be bypassed from within the container.
#
# The tests also verify that a cgroup manager inside the sys container (e.g., systemd)
# can create cgroups inside the sys container and assign resources. Such assignments
# are implicitly constrained by the resources assigned to the sys container itself.
#

load ../helpers/run
load ../helpers/fs
load ../helpers/docker
load ../helpers/cgroups
load ../helpers/systemd
load ../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

function test_cgroup_cpuset() {

	if [ $(nproc) -lt 2 ]; then
		skip "skip (requires host with > 2 processors)"
	fi

	# Run a container and contrain it to cpus [0,1]
	local syscont=$(docker_run --rm --cpuset-cpus="0-1" ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

	#
	# Verify cgroup config looks good at host-level
	#
	declare -A cg_paths
	get_docker_cgroup_paths $syscont cg_paths

	local pid=$(docker_cont_pid $syscont)
	local cgPathHost=${cg_paths[cpuset]}

	echo "cgPathHost = ${cgPathHost}"

	run cat "${cgPathHost}/cpuset.cpus"
	[ "$status" -eq 0 ]
	[[ "$output" == "0-1" ]]

	run cat "${cgPathHost}/cgroup.procs"
	[ "$status" -eq 0 ]
	[[ "$output" == "" ]]

	run cat "${cgPathHost}/${SYSCONT_CGROUP_ROOT}/cpuset.cpus"
	[ "$status" -eq 0 ]
	[[ "$output" == "0-1" ]]

	run cat "${cgPathHost}/${SYSCONT_CGROUP_ROOT}/cgroup.procs"
	[ "$status" -eq 0 ]
	[[ "$output" == "$pid" ]]

	#
	# Verify cgroup config looks good inside the container and delegation works
	#
	cgPathCont="/sys/fs/cgroup/cpuset/"

	docker exec "$syscont" sh -c "cat ${cgPathCont}/cpuset.cpus"
	[ "$status" -eq 0 ]
	[[ "$output" == "0-1" ]]

	docker exec "$syscont" sh -c "cat ${cgPathCont}/cgroup.procs"
	[ "$status" -eq 0 ]
	[ "${lines[0]}" -eq 1 ]

	docker exec "$syscont" sh -c "echo \"0-3\" > ${cgPathCont}/cgroup.procs"
	[ "$status" -eq 1 ]
	[[ "$output" == "sh: write error: Invalid argument" ]]

	docker exec "$syscont" sh -c "echo 1 > ${cgPathCont}/cpuset.cpus"
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c "cat ${cgPathCont}/cpuset.cpus"
	[ "$status" -eq 0 ]
	[[ "$output" == "1" ]]

	# stop the container
	docker_stop "$syscont"

	#
	# verify cgroup dir were cleaned up on host
	#
	for cgdir in ${cg_paths[@]}; do
		echo $cgdir
		[ ! -d "$cgdir" ]
	done
}

function test_cgroup_cpus() {

	# Run a container and give it 10% cpu bandwidth
	local syscont=$(docker_run --rm --cpus="0.1" ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

	#
	# Verify cgroup config looks good at host-level
	#
	declare -A cg_paths
	get_docker_cgroup_paths $syscont cg_paths

	local pid=$(docker_cont_pid $syscont)
	local cgPathHost=${cg_paths[cpu]}

	run cat "${cgPathHost}/cpu.cfs_period_us"
	[ "$status" -eq 0 ]
	[[ "$output" == "100000" ]]

	run cat "${cgPathHost}/cpu.cfs_quota_us"
	[ "$status" -eq 0 ]
	[[ "$output" == "10000" ]]

	run cat "${cgPathHost}/cgroup.procs"
	[ "$status" -eq 0 ]
	[[ "$output" == "" ]]

	run cat "${cgPathHost}/${SYSCONT_CGROUP_ROOT}/cpu.cfs_period_us"
	[ "$status" -eq 0 ]
	[[ "$output" == "100000" ]]

	# The cpu quota is not visible in the child cgroup, though it's enforced
	run cat "${cgPathHost}/${SYSCONT_CGROUP_ROOT}/cpu.cfs_quota_us"
	[ "$status" -eq 0 ]
	[[ "$output" == "-1" ]]

	run cat "${cgPathHost}/${SYSCONT_CGROUP_ROOT}/cgroup.procs"
	[ "$status" -eq 0 ]
	[[ "$output" == "$pid" ]]

	#
	# Verify cgroup config looks good inside the container and delegation works
	#
	cgPathCont="/sys/fs/cgroup/cpu/"

	docker exec "$syscont" sh -c "cat ${cgPathCont}/cpu.cfs_period_us"
	[ "$status" -eq 0 ]
	[[ "$output" == "100000" ]]

	docker exec "$syscont" sh -c "cat ${cgPathCont}/cpu.cfs_quota_us"
	[ "$status" -eq 0 ]
	[[ "$output" == "-1" ]]

	docker exec "$syscont" sh -c "cat ${cgPathCont}/cgroup.procs"
	[ "$status" -eq 0 ]
	[ "${lines[0]}" -eq 1 ]

	docker exec "$syscont" sh -c "echo 10001 > ${cgPathCont}/cpu.cfs_quota_us"
	[ "$status" -eq 1 ]
	[[ "$output" == "sh: write error: Invalid argument" ]]

	docker exec "$syscont" sh -c "echo 9999 > ${cgPathCont}/cpu.cfs_quota_us"
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c "cat ${cgPathCont}/cpu.cfs_quota_us"
	[ "$status" -eq 0 ]
	[[ "$output" == "9999" ]]

	# stop the container
	docker_stop "$syscont"

	#
	# verify cgroup dir were cleaned up on host
	#
	for cgdir in ${cg_paths[@]}; do
		echo $cgdir
		[ ! -d "$cgdir" ]
	done
}

function test_cgroup_memory() {

	# Run a container and give it a max RAM of 16M
	local syscont=$(docker_run --rm --memory="16M" ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

	#
	# Verify cgroup config looks good at host-level
	#
	declare -A cg_paths
	get_docker_cgroup_paths $syscont cg_paths

	local pid=$(docker_cont_pid $syscont)
	local cgPathHost=${cg_paths[memory]}

	run cat "${cgPathHost}/memory.limit_in_bytes"
	[ "$status" -eq 0 ]
	[[ "$output" == "16777216" ]]

	run cat "${cgPathHost}/cgroup.procs"
	[ "$status" -eq 0 ]
	[[ "$output" == "" ]]

	# The mem limit is not visible in the child cgroup, though it's enforced
	run cat "${cgPathHost}/${SYSCONT_CGROUP_ROOT}/memory.limit_in_bytes"
	[ "$status" -eq 0 ]
	[[ "$output" == "9223372036854771712" ]]

	run cat "${cgPathHost}/memory.failcnt"
	[ "$status" -eq 0 ]
	[ "$output" -eq 0 ]

	run cat "${cgPathHost}/${SYSCONT_CGROUP_ROOT}/cgroup.procs"
	[ "$status" -eq 0 ]
	[[ "$output" == "$pid" ]]

	#
	# Verify cgroup config looks good inside the container and delegation works
	#
	cgPathCont="/sys/fs/cgroup/memory/"

	docker exec "$syscont" sh -c "cat ${cgPathCont}/memory.limit_in_bytes"
	[ "$status" -eq 0 ]
	[[ "$output" == "9223372036854771712" ]]

	docker exec "$syscont" sh -c "cat ${cgPathCont}/cgroup.procs"
	[ "$status" -eq 0 ]
	[ "${lines[0]}" -eq 1 ]

	#
	# Inside the sys container, use more mem than what was allocated to it
	#
	docker exec "$syscont" sh -c "mkdir /root/tmp"
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c "mount -t tmpfs -o size=32M tmpfs /root/tmp"
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c "dd if=/dev/zero of=/root/tmp/test bs=1M count=20"
	[ "$status" -eq 0 ]

	# ... and verify it never got across the 16M limit
	docker exec "$syscont" sh -c "cat ${cgPathCont}/memory.usage_in_bytes"
	[ "$status" -eq 0 ]
	[ "$output" -lt "16777216" ]

  	# the memory failcnt counter should be set at host level
	run cat "${cgPathHost}/memory.failcnt"
	[ "$status" -eq 0 ]
	[ "$output" -ge 0 ]

	# ... but zero inside the sys container
	docker exec "$syscont" sh -c "cat ${cgPathCont}/memory.failcnt"
	[ "$status" -eq 0 ]
	[ "$output" -eq 0 ]

	# stop the container
	docker_stop "$syscont"

	#
	# verify cgroup dir were cleaned up on host
	#
	for cgdir in ${cg_paths[@]}; do
		echo $cgdir
		[ ! -d "$cgdir" ]
	done
}

function test_cgroup_perm() {

	local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

	#
	# Verify /sys/fs/cgroup permissions look good inside the container
	#

	docker exec "$syscont" sh -c "ls -lL /sys/fs/cgroup | grep -v rdma | tail -n +2"
	[ "$status" -eq 0 ]

	for file in "${lines[@]}"; do
		verify_perm_owner "drwxr-xr-x" "root" "root" "$file"
	done

	#
	# Verify cgroup permissions look good at host-level
	#

	local files
	declare -A cg_paths
	get_docker_cgroup_paths $syscont cg_paths

	# verify cgroup for sys container is owned by root:root at host level
	for cg_path in ${cg_paths[@]}; do
		run sh -c "ls -lL $cg_path | grep cgroup.procs"
		for file in "${lines[@]}"; do
			verify_owner "root" "root" "$file"
		done
	done

	# verify child cgroup for sys container is owned by the sys container's uid:gid
	local uid=$(docker_root_uid_map $syscont)
	local gid=$(docker_root_gid_map $syscont)

	for cg_path in ${cg_paths[@]}; do
		file=$(ls -lL $cg_path | grep "$SYSCONT_CGROUP_ROOT")
		verify_owner "$uid" "$gid" "$file"

		run sh -c "ls -lL $cg_path/$SYSCONT_CGROUP_ROOT | grep cgroup.procs"
		for file in "${lines[@]}"; do
			verify_owner "$uid" "$gid" "$file"
		done
	done

	docker_stop "$syscont"
}

function test_cgroup_delegation() {

	#
	# Verify cgroup delegation works (e.g., systemd-in-docker can assign cgroups without problem).
	#

	# Launch sys container with systemd
	local syscont=$(docker_run --rm  ${CTR_IMG_REPO}/ubuntu-bionic-systemd-docker)

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

	docker exec "$syscont" sh -c "cat /sys/fs/cgroup/systemd/system.slice/docker.service/cgroup.procs"
	[ "$status" -eq 0 ]
	[[ "$output" == "$inner_docker_pid" ]]

	docker_stop "$syscont"
}

@test "cgroup v1: cpuset" {
	test_cgroup_cpuset
}

@test "cgroup v1: cpus" {
	test_cgroup_cpus
}

@test "cgroup v1: memory" {
	test_cgroup_memory
}

@test "cgroup v1: permissions" {
	test_cgroup_perm
}

@test "cgroup v1: delegation" {
	test_cgroup_delegation
}

@test "cgroup v1 systemd: enable docker systemd driver" {
	if ! systemd_env; then
		skip "no systemd detected"
	fi

	docker-cfg -v --cgroup-driver=systemd
}

@test "cgroup v1 systemd: cpuset" {
	if ! systemd_env; then
		skip "no systemd detected"
	fi

	test_cgroup_cpuset
}

@test "cgroup v1 systemd: cpus" {
	if ! systemd_env; then
		skip "no systemd detected"
	fi

	test_cgroup_cpus
}

@test "cgroup v1 systemd: memory" {
	if ! systemd_env; then
		skip "no systemd detected"
	fi

	test_cgroup_memory
}

@test "cgroup v1 systemd: permissions" {
	if ! systemd_env; then
		skip "no systemd detected"
	fi

	test_cgroup_perm
}

@test "cgroup v1 systemd: delegation" {
	if ! systemd_env; then
		skip "no systemd detected"
	fi

	test_cgroup_delegation
}

@test "cgroup v1 systemd: disable docker systemd driver" {
	if ! systemd_env; then
		skip "no systemd detected"
	fi

	docker-cfg --cgroup-driver=cgroupfs
}

# Verify all is good with the revert back to the Docker cgroupfs driver
@test "cgroup v1: revert" {
	test_cgroup_cpus
}
