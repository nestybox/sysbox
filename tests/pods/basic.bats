#!/usr/bin/env bats

#
# Basic tests for sysbox-pods (i.e., deploying pods with crictl + CRI-O + Sysbox)
#

load ../helpers/crio
load ../helpers/userns
load ../helpers/k8s
load ../helpers/run
load ../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

# Verify the "crictl runp" command (creates an empty pod)
@test "pod create" {

	local pod=$(crictl_runp ${POD_MANIFEST_DIR}/alpine-pod.json)
	local pod_pid=$(crictl_pod_get_pid $pod)

	# Verify the pod's "pause" container is rootless
	container_is_rootless $pod_pid "containers"

	# Verify the pause container's "/proc" has sysbox-fs mounts in it
	cat /proc/${pod_pid}/mountinfo | grep sysboxfs

	crictl stopp $pod
	crictl rmp $pod
}

# Verify the "crictl run" command (creates a pod with containers in it)
@test "pod run" {

	local syscont=$(crictl_run ${POD_MANIFEST_DIR}/alpine-container.json ${POD_MANIFEST_DIR}/alpine-pod.json)
	local syscont_pid=$(crictl_cont_get_pid $syscont)
	local pod=$(crictl_cont_get_pod $syscont)

	# Verify the pod's container is rootless
	container_is_rootless $syscont_pid "containers"

	# Verify the sysbox mounts are present
	cat /proc/${syscont_pid}/mountinfo | grep sysboxfs

	crictl stopp $pod
	crictl rmp $pod
}

# Verify pods with multiple containers in it work properly
@test "multi-container pod" {

	local pod=$(crictl_runp ${POD_MANIFEST_DIR}/alpine-pod.json)
	local syscont1=$(crictl create ${pod} ${POD_MANIFEST_DIR}/alpine-container.json ${POD_MANIFEST_DIR}/alpine-pod.json)
	local syscont2=$(crictl create ${pod} ${POD_MANIFEST_DIR}/alpine-container2.json ${POD_MANIFEST_DIR}/alpine-pod.json)

	crictl start $syscont1
	crictl start $syscont2

	local syscont1_pid=$(crictl_cont_get_pid $syscont1)
	local syscont2_pid=$(crictl_cont_get_pid $syscont1)

	# Verify the pod's containers are rootless
	container_is_rootless $syscont1_pid "containers"
	container_is_rootless $syscont2_pid "containers"

	# Verify the pod's containers share the same user-ns
	local syscont1_userns=$(container_get_userns $syscont1_pid)
	local syscont2_userns=$(container_get_userns $syscont2_pid)

	[[ "$syscont1_userns" == "$syscont2_userns" ]]

	# Verify all containers of a pod see shared sysbox-fs state
	val=$(crictl exec $syscont1 cat /proc/sys/net/netfilter/nf_conntrack_max)
	new_val=$((val - 10))

	crictl exec $syscont1 sh -c "echo $new_val > /proc/sys/net/netfilter/nf_conntrack_max"

	val=$(crictl exec $syscont1 cat /proc/sys/net/netfilter/nf_conntrack_max)
	val2=$(crictl exec $syscont2 cat /proc/sys/net/netfilter/nf_conntrack_max)

	[ $val -eq $new_val ]
	[ $val2 -eq $new_val ]

	new_val=$((val + 20))
	crictl exec $syscont2 sh -c "echo $new_val > /proc/sys/net/netfilter/nf_conntrack_max"

	val=$(crictl exec $syscont1 cat /proc/sys/net/netfilter/nf_conntrack_max)
	val2=$(crictl exec $syscont2 cat /proc/sys/net/netfilter/nf_conntrack_max)

	[ $val -eq $new_val ]
	[ $val2 -eq $new_val ]

	crictl stopp $pod
	crictl rmp $pod
}

# Create multiple pods simultaneously
@test "multiple pods" {

	local syscont1=$(crictl_run ${POD_MANIFEST_DIR}/alpine-container.json ${POD_MANIFEST_DIR}/alpine-pod.json)
	local syscont1_pid=$(crictl_cont_get_pid $syscont1)
	local pod1=$(crictl_cont_get_pod $syscont1)

	local syscont2=$(crictl_run ${POD_MANIFEST_DIR}/alpine-docker-container.json ${POD_MANIFEST_DIR}/alpine-docker-pod.json)
	local syscont2_pid=$(crictl_cont_get_pid $syscont2)
	local pod2=$(crictl_cont_get_pod $syscont2)

	# Verify the pod's containers are in different user-ns
	local syscont1_userns=$(container_get_userns $syscont1_pid)
	local syscont2_userns=$(container_get_userns $syscont2_pid)

	[ $syscont1_userns -ne $syscont2_userns ]

	# Verify each pod sees it's own sysbox-fs state
	val=$(crictl exec $syscont1 cat /proc/sys/net/netfilter/nf_conntrack_max)
	new_val=$((val - 10))

	crictl exec $syscont1 sh -c "echo $new_val > /proc/sys/net/netfilter/nf_conntrack_max"

	val=$(crictl exec $syscont1 cat /proc/sys/net/netfilter/nf_conntrack_max)
	val2=$(crictl exec $syscont2 cat /proc/sys/net/netfilter/nf_conntrack_max)

	[ $val -eq $new_val ]
	[ $val2 -ne $new_val ]

	crictl stopp $pod1 $pod2
	crictl rmp $pod1 $pod2
}

# Verify Docker works correctly inside a sysbox pod
@test "docker-in-pod" {

	skip "Sysbox issue #863"

	local syscont=$(crictl_run ${POD_MANIFEST_DIR}/alpine-docker-container.json ${POD_MANIFEST_DIR}/alpine-docker-pod.json)
	local pod=$(crictl_cont_get_pod $syscont)

	# Launching a background process with crictl fails due to a sysbox seccomp
	# notif tracking bug; see sysbox issue #863.
	crictl exec -s $syscont sh -c "dockerd > /var/log/dockerd.log 2>&1 &"
	crictl_wait_for_inner_dockerd $syscont

	crictl exec $syscont sh -c "docker run ${CTR_IMG_REPO}/hello-world | grep \"Hello from Docker!\""

	crictl stopp $pod
	crictl rmp $pod
}

# Verify systemd works correctly inside a sysbox pod
@test "systemd-in-pod" {

	local syscont=$(crictl_run ${POD_MANIFEST_DIR}/ubu-bionic-systemd-docker-container.json ${POD_MANIFEST_DIR}/ubu-bionic-systemd-docker-pod.json)
	local pod=$(crictl_cont_get_pod $syscont)

	# We need a better way to wait for systemd; I tried "retry run" with "crictl
	# exec" to check for "systemctl status", but it does not work (i.e., the
	# retry_run returns earlier than expected, when systemd is still no ready).
	sleep 10

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

# @test "pod hostPath vol" {

# 	# Create a host dir and files within it; root ownership.

# 	# Create a pod with a volume mount of that host dir

# 	pod_id=$(crictl runp "$TESTDATA"/sandbox_config.json)

# 	host_path="$TESTDIR"/clash
# 	mkdir "$host_path"
# 	echo "clashing..." > "$host_path"/clashing.txt

# 	config="$TESTDIR"/config.json
# 	jq --arg host_path "$host_path" --arg ctr_path /run/secrets/clash \
# 		'  .mounts = [ {
# 			host_path: $host_path,
# 			container_path: $ctr_path
# 		} ]' \
# 		"$TESTDATA"/container_redis.json > "$config"
# 	ctr_id=$(crictl create "$pod_id" "$config" "$TESTDATA"/sandbox_config.json)

# 	crictl exec --sync "$ctr_id" ls -la /run/secrets/clash

# 	output=$(crictl exec --sync "$ctr_id" cat /run/secrets/clash/clashing.txt)
# 	[[ "$output" == "clashing..."* ]]

# 	crictl exec --sync "$ctr_id" ls -la /run/secrets
# 	output=$(crictl exec --sync "$ctr_id" cat /run/secrets/test.txt)
# 	[[ "$output" == "Testing secrets mounts. I am mounted!"* ]]


# 	# From inside the pod, verify permissions look good

# 	# Cleanup

# }

# TODO
#
# Verify pod storage (volume mounts & uid-shifting)
# Verify pod networking
# Verify pod security (exclusive uid mappings)
# Verify pod performance (startup)
# Verify pod cgroup limits
# Verify pod with read-only rootfs
# Verify inner docker image sharing with pods (once it's implemented)
# Verify K8s.io KinD runs inside a pod
