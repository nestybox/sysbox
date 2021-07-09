#!/bin/bash -e
#
# Script to run Sysbox-PODs integration testcases in the supported platforms --
# only Ubuntu for now.
#

function main() {

	# Argument testName is optional.
	if [ $# -eq 1 ]; then
		printf "\nExecuting $1 ... \n"
		bats --tap $1
		exit 0
	fi

	docker system prune -a -f

	printf "\nExecuting sysbox-pod tests ... \n"

	bats --tap tests/pods/basic.bats
	bats --tap tests/pods/mounts.bats
	bats --tap tests/pods/systemd-in-pods.bats
	bats --tap tests/pods/docker-in-pod.bats
	bats --tap tests/pods/k8s-in-pod.bats

	if command -v crictl > /dev/null 2>&1; then
		crictl rmi --all
	fi
}

main "$@"
