#!/bin/bash

#
# Cgroup Test Helper Functions
#
# Note: for tests using bats.
#

. $(dirname ${BASH_SOURCE[0]})/systemd.bash

# Name of dir for sys container delegation boundary
export SYSCONT_CGROUP_ROOT="syscont-cgroup-root"

function get_docker_cgroup_driver() {
	ret=$(sh -c "docker info 2>/dev/null | grep 'Cgroup Driver:'")
	ret=$(echo $ret | awk '{print $3}')
	echo $ret
}

function get_docker_cgroup_v1_fs_paths() {
	local syscont=$1
	local -n ___cgp=$2
	local cgControllers=$(ls /sys/fs/cgroup | grep -v "unified" | grep -v "systemd" | grep -v "rdma")

	for controller in ${cgControllers[@]}; do
		___cgp[$controller]="/sys/fs/cgroup/$controller/docker/$syscont"
	done
}

function get_docker_cgroup_v1_systemd_paths() {
	local syscont=$1
	local -n ___cgp=$2
	local cgControllers=$(ls /sys/fs/cgroup | grep -v "unified" | grep -v "systemd" | grep -v "rdma")

	for controller in ${cgControllers[@]}; do
		___cgp[$controller]="/sys/fs/cgroup/$controller/system.slice/docker-$syscont.scope"
	done
}

function get_docker_cgroup_v1_paths() {
	local syscont=$1
	local -n __cgp=$2
	local docker_cgroup_driver=$(get_docker_cgroup_driver)

	echo "docker_cgroup_driver = $docker_cgroup_driver"

	if [[ "$docker_cgroup_driver" == "systemd" ]]; then
		get_docker_cgroup_v1_systemd_paths $syscont __cgp
	else
		get_docker_cgroup_v1_fs_paths $syscont __cgp
	fi

}

# Given a Docker container id, populates global var $CG_PATHS with its cgroup paths.
#
# E.g.,
#
# CG_PATHS[cpu]=/sys/fs/cgroup/cpu/docker/<container-id>
# CG_PATHS[memory]=/sys/fs/cgroup/memory/docker/<container-id>
# ...
function get_docker_cgroup_paths() {
	local syscont=$(docker_cont_full_id $1)
	local -n _cgp=$2
	get_docker_cgroup_v1_paths $syscont _cgp
}
