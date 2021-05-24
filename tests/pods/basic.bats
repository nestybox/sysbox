#!/usr/bin/env bats

#
# Basic tests for sysbox-pods (i.e., deploying pods with crictl + CRI-O + Sysbox)
#

load ../helpers/run
load ../helpers/crio
load ../helpers/userns
load ../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

# Verify the "crictl runp" command
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

# Verify the "crictl run" command
@test "pod run" {

	local syscont=$(crictl_run ${POD_MANIFEST_DIR}/alpine-container.json ${POD_MANIFEST_DIR}/alpine-pod.json)
	local syscont_pid=$(crictl_cont_get_pid $syscont)
	local pod=$(crictl_cont_get_pod $syscont)

	# Verify the pod's container is rootless
	container_is_rootless $syscont_pid "containers"

	# Verify the sysbox mounts are present
	cat /proc/${syscont_pid}/mountinfo | grep sysboxfs

	# Cleanup
	crictl stopp $pod
	crictl rmp $pod
}

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

	# Cleanup
	crictl stopp $pod
	crictl rmp $pod
}

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

	# Cleanup
	crictl stopp $pod1 $pod2
	crictl rmp $pod1 $pod2
}

# @test "docker-in-pod" {

# 	# Verify Docker works inside the sysbox pod

# }

# @test "systemd-in-pod" {

# 	# Verify Docker works inside the sysbox pod

# }

# @test "k8s-in-pod" {

# 	# Verify K8s works inside the sysbox pod
# }


# TODO
#
# Verify pod storage (volume mounts & uid-shifting)
# Verify pod networking
# Verify pod security
# Verify pod performance (startup)
# Verify inner docker image sharing with pods (once it's implemented)
