#!/bin/bash

#
# Cgroup Test Helper Functions
#
# Note: for tests using bats.
#

. $(dirname ${BASH_SOURCE[0]})/systemd.bash

# Name of dir for sys container delegation boundary (cgroup v1 only)
export SYSCONT_CGROUP_ROOT="syscont-cgroup-root"

# Name of dir for sys container init processes (cgroup v2 only)
export SYSCONT_CGROUP_INIT="init.scope"

function host_is_cgroup_v2() {
	if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
		return 0
	else
		return 1
	fi
}

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

# Given a Docker container id, populates global var $CG_PATHS with its cgroup v1 paths.
#
# E.g.,
#
# CG_PATHS[cpu]=/sys/fs/cgroup/cpu/docker/<container-id>
# CG_PATHS[memory]=/sys/fs/cgroup/memory/docker/<container-id>
# ...
function get_docker_cgroupv1_paths() {
	local syscont=$(docker_cont_full_id $1)
	local -n _cgp=$2
	get_docker_cgroup_v1_paths $syscont _cgp
}

function get_docker_cgroupv2_controllers() {
	local docker_cgroup_driver=$(get_docker_cgroup_driver)

	if [[ "$docker_cgroup_driver" == "systemd" ]]; then
		cat "/sys/fs/cgroup/system.slice/cgroup.subtree_control"
	else
		cat "/sys/fs/cgroup/docker/cgroup.subtree_control"
	fi
}

# Given a Docker container id, returns its cgroup v2 path
function get_docker_cgroupv2_path() {
	local syscont=$(docker_cont_full_id $1)
	local docker_cgroup_driver=$(get_docker_cgroup_driver)

	if [[ "$docker_cgroup_driver" == "systemd" ]]; then
		echo "/sys/fs/cgroup/system.slice/docker-$syscont.scope"
	else
		echo "/sys/fs/cgroup/docker/$syscont"
	fi
}
