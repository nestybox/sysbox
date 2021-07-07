#!/usr/bin/env bats

#
# Tests for running systemd in sysbox-pods.
#

load ../helpers/crio
load ../helpers/userns
load ../helpers/k8s
load ../helpers/run
load ../helpers/sysbox-health

function setup() {
	# Sysbox-Pods are only supported in Ubuntu distros for now.
	local distro=$(get_host_distro)
	if [[ ${distro} != "ubuntu" ]]; then
		skip "Sysbox-pods feature not supported in ${distro} distro"
	fi
}

function teardown() {
  sysbox_log_check
}

# Verify systemd works correctly inside a sysbox pod
@test "systemd-in-pod" {

	local syscont=$(crictl_run ${POD_MANIFEST_DIR}/ubu-focal-systemd-docker-container.json ${POD_MANIFEST_DIR}/ubu-focal-systemd-docker-pod.json)
	local pod=$(crictl_cont_get_pod $syscont)

	# We need a better way to wait for systemd; I tried "retry run" with "crictl
	# exec" to check for "systemctl status", but it does not work (i.e., the
	# retry_run returns earlier than expected, when systemd is still no ready).
	sleep 20

	run crictl exec $syscont sh -c "systemctl status"
	[ "$status" -eq 0 ]
	[[ "${lines[1]}" =~ "State: running" ]]

	run crictl exec $syscont systemd-detect-virt
	[ "$status" -eq 0 ]
	[[ "$output" == "container-other" ]]

	run crictl exec $syscont sh -c \
       "systemctl status systemd-journald.service | egrep \"active \(running\)\""
	[ "$status" -eq 0 ]

	run crictl exec $syscont systemctl restart systemd-journald.service
	[ "$status" -eq 0 ]

	sleep 2

	run crictl exec $syscont sh -c \
       "systemctl status systemd-journald.service | egrep \"active \(running\)\""
	[ "$status" -eq 0 ]

	# verify systemd started docker and all is well
	crictl exec $syscont sh -c "docker run ${CTR_IMG_REPO}/hello-world | grep \"Hello from Docker!\""

	crictl stopp $pod
	crictl rmp $pod
}
