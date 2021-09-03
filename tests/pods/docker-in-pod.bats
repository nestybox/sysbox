#!/usr/bin/env bats

#
# Tests for running Docker in sysbox-pods.
#

load ../helpers/crio
load ../helpers/userns
load ../helpers/k8s
load ../helpers/net
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
@test "docker cli+eng in one pod" {

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

# Launch two pods, one with docker CLI and the other with Docker's dind image,
# and verify all is good.
@test "docker-cli + dind 19.03 pods" {

	local eng=$(crictl_run ${POD_MANIFEST_DIR}/dind-19.03-container.json ${POD_MANIFEST_DIR}/dind-pod.json)
	local pod1=$(crictl_cont_get_pod $eng)

	local cli=$(crictl_run ${POD_MANIFEST_DIR}/docker-cli-container.json ${POD_MANIFEST_DIR}/docker-cli-pod.json)
	local pod2=$(crictl_cont_get_pod $cli)

	# Get the IP address of the Docker engine pod
	run crictl exec $eng sh -c "ip a"
	[ "$status" -eq 0 ]
	local eng_ip=$(parse_ip "$output" "eth0")

	# Connect the Docker CLI pod to the engine pod
	crictl exec $cli sh -c "docker context create --docker host=tcp://${eng_ip}:2375 ctx"
	crictl exec $cli sh -c "docker context use ctx"

	# Verify docker pull of nginx image works (issue 254)
	crictl exec $cli sh -c "docker pull nginx"

	# Run an inner nginx
	crictl exec $cli sh -c "docker run -p 8080:80 -d --rm nginx"

	# Verify the Docker CLI sees the nginx service
	run crictl exec $cli sh -c "apk add curl && curl -S ${eng_ip}:8080"
	[[ "$output" =~ "Welcome to nginx!" ]]

	# Verify the host also sees it
	run curl -S ${eng_ip}:8080
	[[ "$output" =~ "Welcome to nginx!" ]]

	crictl exec $cli sh -c "docker stop -t0 \$(docker ps -aq)"

	crictl stopp $pod1 $pod2
	crictl rmp $pod1 $pod2
}

# Launch two pods, one with docker CLI and the other with Docker's dind image,
# and verify all is good.
@test "docker-cli + dind 20.10 pods" {

	local eng=$(crictl_run ${POD_MANIFEST_DIR}/dind-20.10-container.json ${POD_MANIFEST_DIR}/dind-pod.json)
	local pod1=$(crictl_cont_get_pod $eng)

	local cli=$(crictl_run ${POD_MANIFEST_DIR}/docker-cli-container.json ${POD_MANIFEST_DIR}/docker-cli-pod.json)
	local pod2=$(crictl_cont_get_pod $cli)

	# Get the IP address of the Docker engine pod
	run crictl exec $eng sh -c "ip a"
	[ "$status" -eq 0 ]
	local eng_ip=$(parse_ip "$output" "eth0")

	# Connect the Docker CLI pod to the engine pod
	crictl exec $cli sh -c "docker context create --docker host=tcp://${eng_ip}:2375 ctx"
	crictl exec $cli sh -c "docker context use ctx"

	# For some reason, docker 20.10 takes longer to setup
	sleep 20

	# Verify docker pull of nginx image works (issue 254)
	crictl exec $cli sh -c "docker pull nginx"

	# Run an inner nginx
	crictl exec $cli sh -c "docker run -p 8080:80 -d --rm nginx"

	# Verify the Docker CLI sees the nginx service
	run crictl exec $cli sh -c "apk add curl && curl -S ${eng_ip}:8080"
	[[ "$output" =~ "Welcome to nginx!" ]]

	# Verify the host also sees it
	run curl -S ${eng_ip}:8080
	[[ "$output" =~ "Welcome to nginx!" ]]

	crictl exec $cli sh -c "docker stop -t0 \$(docker ps -aq)"

	crictl stopp $pod1 $pod2
	crictl rmp $pod1 $pod2
}
