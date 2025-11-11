#!/bin/bash

. $(dirname ${BASH_SOURCE[0]})/environment.bash

function get_inner_docker_graphdriver() {
	local sysbox_backing_fs=$(get_sysbox_backing_fs)
	if [[ "$sysbox_backing_fs" == "btrfs" ]]; then
		echo "btrfs"
	else
		echo "overlay2"
	fi
}

function check_inner_docker_graphdriver() {
	local syscont=$1
	local docker_info=$2
	local expect_graphdriver=$(get_inner_docker_graphdriver)
	echo "$docker_info" | egrep -i "Storage Driver: $expect_graphdriver"
}
