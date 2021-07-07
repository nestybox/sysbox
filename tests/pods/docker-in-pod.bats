#!/usr/bin/env bats

#
# Tests for running Docker in sysbox-pods.
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

# Verify Docker works correctly inside a sysbox pod
@test "docker-in-pod" {

	# TODO: works when "--seccomp-fd-release" is passed to sysbox-fs.
	skip "Sysbox issue #863"

	local syscont=$(crictl_run ${POD_MANIFEST_DIR}/alpine-docker-container.json ${POD_MANIFEST_DIR}/alpine-docker-pod.json)
	local pod=$(crictl_cont_get_pod $syscont)

	# Launching a background process with crictl fails due to a sysbox seccomp
	# notif tracking bug; see sysbox issue #863.
	crictl exec $syscont sh -c "dockerd > /var/log/dockerd.log 2>&1 &"
	crictl_wait_for_inner_dockerd $syscont

	crictl exec $syscont sh -c "docker run ${CTR_IMG_REPO}/hello-world | grep \"Hello from Docker!\""

	crictl stopp $pod
	crictl rmp $pod
}
