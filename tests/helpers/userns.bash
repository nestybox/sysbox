#!/bin/bash

function container_is_rootless() {

	local container_pid=$1
	local subid_user=$2

	local uid=$(cat /proc/${container_pid}/uid_map | awk '{print $2}')
	local gid=$(cat /proc/${container_pid}/gid_map | awk '{print $2}')

	# TODO: improve this by checking that the given container's uid is within the
	# range of the subuid; currently this only checks that the container's uid
	# matches the first subuid in the range

   local subuid=$(grep ${subid_user} /etc/subuid | cut -d":" -f2)
   local subgid=$(grep ${subid_user} /etc/subgid | cut -d":" -f2)

	if [ $uid -ne $subuid ]; then
		return 1
	fi

	if [ $gid -ne $subgid ]; then
		return 1
	fi

	return 0
}

function container_get_userns() {
	local container_pid=$1
	local link=$(readlink /proc/${container_pid}/ns/user)
	local userns=$(echo $link | cut -d ":" -f 2 | tr -d "[]")
	echo $userns
}

function sysbox_get_subuid_range_start() {
	local start=$(grep sysbox /etc/subuid | cut -d ":" -f2)
	echo $start
}

function sysbox_get_subuid_range_size() {
	local size=$(grep sysbox /etc/subuid | cut -d ":" -f3)
	echo $size
}
