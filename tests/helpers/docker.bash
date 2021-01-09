#!/bin/bash

#
# Docker Test Helper Functions
#
# Note: for tests using bats.
#

. $(dirname ${BASH_SOURCE[0]})/run.bash

function wait_for_dockerd {
  retry_run 10 1 "docker ps"
}

function wait_for_inner_dockerd {
  local syscont=$1
  retry_run 10 1 "__docker exec $syscont docker ps"
}

function docker_cont_ip() {
  local cont=$1
  local ip=$(__docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $cont)
  echo $ip
}

# Given a container's short id, returns its full id
function docker_cont_full_id() {
  local cont=$1
  local syscont_full_id=$(__docker inspect --format='{{.Id}}' $cont)
  echo $syscont_full_id
}

function docker_cont_image_id() {
  local cont=$1
  local image_id=$(__docker inspect --format='{{.Image}}' $cont)
  echo $image_id
}

# Get the host's uid assigned to the container's root user
function docker_root_uid_map() {
  local cont=$1
  local uid=$(__docker exec "$cont" sh -c "cat /proc/self/uid_map | awk '{print \$2}'")
  echo $uid
}

# Get the host's gid assigned to the container's root user
function docker_root_gid_map() {
  local cont=$1
  local gid=$(__docker exec "$cont" sh -c "cat /proc/self/gid_map | awk '{print \$2}'")
  echo $gid
}

function docker_cont_rootfs() {
  local cont=$1
  local rootfs=$(__docker inspect --format='{{json .GraphDriver}}' $cont | jq .Data.MergedDir | tr -d '"')
  echo $rootfs
}

function docker_cont_pid() {
	local cont=$1
	local pid=$(__docker inspect -f '{{.State.Pid}}' $cont)
	echo $pid
}

# Helper for getDockerCgroupPaths, when using cgroups v1
function getDockerCgroupV1Paths() {
	local syscont=$1
	local -n __cgp=$2
	local cgControllers=$(ls /sys/fs/cgroup | grep -v "unified" | grep -v "systemd" | grep -v "rdma")

	# TODO: add support for when Docker is configured to use the systemd cgroup driver
	for controller in ${cgControllers[@]}; do
		__cgp[$controller]="/sys/fs/cgroup/$controller/docker/$syscont"
	done
}

# Given a Docker container id, populates global var $CG_PATHS with its cgroup paths.
#
# E.g.,
#
# CG_PATHS[cpu]=/sys/fs/cgroup/cpu/docker/<container-id>
# CG_PATHS[memory]=/sys/fs/cgroup/memory/docker/<container-id>
# ...
function getDockerCgroupPaths() {
	local syscont=$(docker_cont_full_id $1)
	local -n _cgp=$2
	# TODO: add support for cgroups v2
	getDockerCgroupV1Paths $syscont _cgp
}
