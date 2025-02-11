#!/usr/bin/env bats

#
# Docker Test Helper Functions
#

load $(dirname ${BASH_SOURCE[0]})/run.bash
load $(dirname ${BASH_SOURCE[0]})/systemd.bash

# Need this to avoid recursion on docker()
function __docker() {
  command docker "$@"
}

# Wrapper for docker using bats
function docker() {
  run __docker "$@"

  # Debug info
  echo "docker $@ (status=$status):" >&2
  echo "$output" >&2
}

# Executes docker run with sysbox-runc; returns the container id
function docker_run() {
  docker run --runtime=sysbox-runc -d "$@"
  [ "$status" -eq 0 ]

  docker ps --format "{{.ID}}"
  [ "$status" -eq 0 ]

  echo "$output" | head -1
}

# Stops a docker container immediately
function docker_stop() {
  [[ "$#" == 1 ]]

  local id="$1"

  echo "Stopping $id ..."

  if [ -z "$id" ]; then
    return 1
  fi

  docker stop -t0 "$id"
}

# Docker daemon start
function dockerd_start() {
  if systemd_env; then
    systemctl start docker.service
    sleep 2
  else
    bats_bg dockerd $@ > /var/log/dockerd.log 2>&1
    sleep 2
  fi
}

# Docker daemon stop
function dockerd_stop() {
  if systemd_env; then
    systemctl stop docker.service
    sleep 1
  else
    local pid=$(pidof dockerd)
    kill $pid
    sleep 1
    if [ -f /var/run/docker.pid ]; then rm /var/run/docker.pid; fi
  fi
}

# Wait for docker daemon to start
function wait_for_dockerd {
  retry_run 10 1 "docker ps"
}

# Wait for docker daemon inside sysbox container to start
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

# Indicates if docker is using the containerd image store
function docker_containerd_image_store() {
  __docker info -f '{{json .DriverStatus}}' | egrep -q "driver-type.+io.containerd.snapshotter.v1"
}

function docker_cont_rootfs() {
  local cont=$1
  if docker_containerd_image_store; then
    local id=$(docker_cont_full_id $cont)
    local driver=$(__docker info -f '{{json .Driver}}' |  tr -d '"')
    local rootfs="/var/lib/docker/rootfs/$driver/$id"
  else
    local rootfs=$(__docker inspect --format='{{json .GraphDriver}}' $cont | jq .Data.MergedDir | tr -d '"')
  fi

  echo $rootfs
}

function docker_cont_rootfs_upper_dir() {
  local cont=$1
  if docker_containerd_image_store; then
    local rootfs=$(docker_cont_rootfs $cont)
    local upperdir=$(mount | grep $rootfs | grep -oP '(?<=upperdir=)[^,)]*')
  else
    local upperdir=$(__docker inspect --format='{{json .GraphDriver}}' $cont | jq .Data.UpperDir | tr -d '"')
  fi
  echo $upperdir
}

function docker_cont_pid() {
  local cont=$1
  local pid=$(__docker inspect -f '{{.State.Pid}}' $cont)
  echo $pid
}

function docker_userns_remap() {
  __docker info -f '{{json .SecurityOptions}}' | grep -q "name=userns"
}

# Configures key-based (passwordless) ssh access in a docker container.
function docker_ssh_access() {
  local cont=$1
  local pubkey=$(cat ~/.ssh/id_rsa.pub)

  __docker exec $cont bash -c "mkdir -p ~/.ssh && echo $pubkey > ~/.ssh/authorized_keys"
}

function docker_engine_version() {
	local res=$(__docker info --format '{{json .}}' | jq ".ServerVersion" | tr -d '"')
	echo $res
}

function docker_group_id() {
	res=$(grep docker /etc/group | cut -d ":" -f 3)
	echo $res
}
