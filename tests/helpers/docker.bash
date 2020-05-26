#!/bin/bash

#
# Docker Test Helper Functions
#
# Note: for tests using bats.
#

load ../helpers/run

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
