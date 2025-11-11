#!/usr/bin/env bats

#
# Tests for running Docker in sysbox-pods.
#

load ../helpers/crictl
load ../helpers/userns
load ../helpers/k8s
load ../helpers/net
load ../helpers/run
load ../helpers/cgroups
load ../helpers/sysbox-health

function setup() {
	run which crictl
	if [ $status -ne 0 ]; then
		skip "crictl not installed"
	fi
}

function teardown() {
  sysbox_log_check
}

# Verify Docker works correctly inside a sysbox pod
@test "docker cli+eng in one pod" {

	local syscont=$(crictl_run ${POD_MANIFEST_DIR}/alpine-docker-container.json ${POD_MANIFEST_DIR}/alpine-docker-pod.json)
	local pod=$(crictl_cont_get_pod $syscont)

	crictl_wait_for_inner_dockerd $syscont

	crictl exec $syscont sh -c "docker run ${CTR_IMG_REPO}/hello-world | grep \"Hello from Docker!\""

	crictl exec $syscont sh -c "docker pull ${CTR_IMG_REPO}/nginx"
	crictl exec $syscont sh -c "docker run -p 8080:80 -d --rm ${CTR_IMG_REPO}/nginx"
	run crictl exec $syscont sh -c "apk add curl && curl -S localhost:8080"
	[[ "$output" =~ "Welcome to nginx!" ]]

	crictl stop -t 5 $syscont
	crictl stopp $pod
	crictl rmp $pod
}

# Launch two pods, one with docker CLI and the other with Docker's dind image,
# and verify all is good.
@test "docker-cli + dind 19.03 pods" {

	if host_is_cgroup_v2; then
		skip "needs cgroup v1 host"
	fi

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
	crictl exec $cli sh -c "docker pull ${CTR_IMG_REPO}/nginx"

	# Run an inner nginx
	crictl exec $cli sh -c "docker run -p 8080:80 -d --rm ${CTR_IMG_REPO}/nginx"

	# Verify the Docker CLI sees the nginx service
	run crictl exec $cli sh -c "apk add curl && curl -S ${eng_ip}:8080"
	[[ "$output" =~ "Welcome to nginx!" ]]

	# Verify the host also sees it
	run curl -S ${eng_ip}:8080
	[[ "$output" =~ "Welcome to nginx!" ]]

	crictl exec $cli sh -c "docker stop -t0 \$(docker ps -aq)"

	crictl stop -t 5 $eng $cli
	crictl stopp $pod1 $pod2
	crictl rmp $pod1 $pod2
}

# Launch two pods, one with docker CLI and the other with Docker's dind image,
# and verify all is good.
@test "docker-cli + dind 29.0 pods" {

	local eng=$(crictl_run ${POD_MANIFEST_DIR}/dind-29.0-container.json ${POD_MANIFEST_DIR}/dind-pod.json)
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
	crictl exec $cli sh -c "docker pull ${CTR_IMG_REPO}/nginx"

	# Run an inner nginx
	crictl exec $cli sh -c "docker run -p 8080:80 -d --rm ${CTR_IMG_REPO}/nginx"

	# Verify the Docker CLI sees the nginx service
	run crictl exec $cli sh -c "apk add curl && curl -S ${eng_ip}:8080"
	[[ "$output" =~ "Welcome to nginx!" ]]

	# Verify the host also sees it
	run curl -S ${eng_ip}:8080
	[[ "$output" =~ "Welcome to nginx!" ]]

	crictl exec $cli sh -c "docker stop -t0 \$(docker ps -aq)"

	crictl stop -t 5 $eng $cli
	crictl stopp $pod1 $pod2
	crictl rmp $pod1 $pod2
}
