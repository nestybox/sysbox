#!/usr/bin/env bats

#
# Tests for deploying a K0s cluster inside system container nodes.
#

load ../helpers/run
load ../helpers/k8s
load ../helpers/sysbox-health

# Basic test to verify k0s control plane comes up
@test "k0s control-plane up" {

	if [[ $(get_platform) != "amd64" ]]; then
		skip "K0s testcase supported only in amd64 architecture"
	fi

	k8s_check_sufficient_storage

	docker run -d --rm --name k0s --hostname k0s --runtime=sysbox-runc -p 6443:6443 docker.io/k0sproject/k0s:latest
	[ "$status" -eq 0 ]

	# Wait for k0s to come up
	sleep 60

	docker exec k0s kubectl get nodes
	[ "$status" -eq 0 ]
	[[ "${lines[1]}" =~ "k0s".+"Ready" ]]

	docker stop -t0 k0s
}
