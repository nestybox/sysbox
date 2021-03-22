#!/bin/bash

. $(dirname ${BASH_SOURCE[0]})/run.bash

export POD_MANIFEST_DIR=/root/nestybox/sysbox/tests/pods/manifests

# Given a pod's ID, return the associated host pid (i.e., the pid of the pod's pause container)
function crictl_pod_get_pid() {
	crictl inspectp $1 | jq ".info.pid"
}

# Given a pod's container ID, return the associated host pid
function crictl_cont_get_pid() {
	crictl inspect $1 | jq ".info.pid"
}

# Given a pod's container ID, return the associated pod ID
function crictl_cont_get_pod() {
	crictl inspect $1 | jq ".info.sandboxID" | tr -d '"'
}

# Get the host's uid assigned to the container's root user (user-ns mapping)
function crictl_root_uid_map() {
  local cont=$1
  local uid=$(crictl exec "$cont" sh -c "cat /proc/self/uid_map | awk '{print \$2}'")
  echo $uid
}

# Get the host's gid assigned to the container's root user (user-ns mapping)
function crictl_root_gid_map() {
  local cont=$1
  local gid=$(crictl exec "$cont" sh -c "cat /proc/self/gid_map | awk '{print \$2}'")
  echo $gid
}
