#!/bin/bash -e
#
# Script to run Sysbox integration testcases to validate Kubernetes-in-Docker (Kind)
# support.
#

# Finds out if selinux is enabled by looking at the file-system extended attributes.
function selinux_on() {
	if ls -l /proc/uptime | cut -d" " -f1 | tail -c 2 | egrep -q "\."; then
		return 0
	else
		return 1
	fi
}

function main() {

	progName=$(basename "$0")

	# Argument testName is optional.
	if [ $# -eq 1 ]; then
		printf "\nExecuting $1 ... \n"
		bats --tap $1
		exit 0
	fi

	# the kind tests need plenty storage (otherwise kubelet fails);
	# remove all docker images from prior tests to make room, and
	# remove all docker images after test too.
	printf "\n"
	docker system prune -a -f

	printf "\nExecuting kind testcases with flannel cni ... \n"
	bats --tap tests/kind/kind-flannel.bats

	printf "\nExecuting kind testcases with custom docker networks ... \n"
	bats --tap tests/kind/kind-custom-net.bats

	# Skip k3s testcases if se-linux feature is activated (currently in experimental
	# state by K3s).
	if selinux_on; then
		printf "\nSkipping k3s testcases due to SElinux activation ... \n"
	else
		printf "\nExecuting k3s testcases with flannel cni ... \n"
		bats --tap tests/kind/k3s-flannel.bats
	fi

	printf "\n"
	docker system prune -a -f
}

main "$@"
