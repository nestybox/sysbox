#!/bin/bash -e
#
# Script to run Sysbox-PODs integration testcases in the supported platforms --
# only Ubuntu for now.
#

# Returns linux distro running in the system.
function get_host_distro() {
	local distro=$(cat /etc/os-release | awk -F"=" '/^ID=/ {print $2}' | tr -d '"')
	echo $distro
}

function main() {

	local distro=$(get_host_distro)

	if [[ ${distro} != "ubuntu" ]]; then
		printf "\nSkipping sysbox-pods tests in unsupported distro: %s\n", ${distro}
		exit 0
	fi

	# Argument testName is optional
	if [ $# -eq 1 ]; then
		printf "\nExecuting $1 ... \n"
		bats --tap $1
		exit 0
	fi

	# sysbox-pods tests
	docker system prune -a -f
	printf "\nExecuting sysbox-pod tests ... \n"
	bats --tap tests/pods
	crictl rmi --all
}

main "$@"
