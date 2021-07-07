#!/usr/bin/env bats

#
# Volume mount tests for sysbox-pods.
#

load ../helpers/crio
load ../helpers/userns
load ../helpers/k8s
load ../helpers/run
load ../helpers/uid-shift
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

@test "pod hostPath vol" {

	# Create a dir on the host with ownership matching the sys container's root
	# process.
	local host_path=$(mktemp -d "${WORK_DIR}/tmp-vol.XXXXXX")
	echo "some data" > $host_path/testfile.txt

	subuid=$(grep containers /etc/subuid | cut -d":" -f2)
	subgid=$(grep containers /etc/subgid | cut -d":" -f2)
   chown -R $subuid:$subgid $host_path

	# Create a pod with a volume mount of that host dir
	local ctr_path="/mnt/test-vol"
	local container_json="${WORK_DIR}/container.json"

	jq --arg host_path "$host_path" --arg ctr_path "$ctr_path" \
		'  .mounts = [ {
   			host_path: $host_path,
	   		container_path: $ctr_path
		} ]' \
	   "${POD_MANIFEST_DIR}/alpine-container.json" > "$container_json"

	local syscont=$(crictl_run $container_json ${POD_MANIFEST_DIR}/alpine-pod.json)
	local pod=$(crictl_cont_get_pod $syscont)

	# Verify the volume got mounted and it has the correct ownership
	run crictl exec $syscont cat "$ctr_path/testfile.txt"
	[ "$status" -eq 0 ]
	[[ "$output" == "some data" ]]

	uid=$(crictl exec $syscont stat -c '%u' $ctr_path)
	gid=$(crictl exec $syscont stat -c '%g' $ctr_path)

	[ $uid -eq 0 ]
	[ $gid -eq 0 ]

	# Verify shiftfs is NOT mounted on the pod's volume
	run crictl exec $syscont sh -c "grep $ctr_path /proc/self/mountinfo | grep shiftfs"
	[ "$status" -ne 0 ]

	# Verify the pod can write to the mounted host volume
	run crictl exec $syscont sh -c "echo 'new data' > $ctr_path/testfile.txt"
	[ "$status" -eq 0 ]

	run crictl exec $syscont cat "$ctr_path/testfile.txt"
	[ "$status" -eq 0 ]
	[[ "$output" == "new data" ]]

	# Cleanup
	crictl stopp $pod
	crictl rmp $pod
	rm -rf $host_path
	rm -rf $container_json
}

@test "pod hostPath vol (uid-shift)" {

	if ! host_supports_uid_shifting; then
		skip "needs host uid shifting support"
	fi

	# Create a dir on the host with root ownership
	local host_path=$(mktemp -d "${WORK_DIR}/tmp-vol.XXXXXX")
	echo "some data" > $host_path/testfile.txt

	# Create a pod with a volume mount of that host dir
	local ctr_path="/mnt/test-vol"
	local container_json="${WORK_DIR}/container.json"

	jq --arg host_path "$host_path" --arg ctr_path "$ctr_path" \
		'  .mounts = [ {
   			host_path: $host_path,
	   		container_path: $ctr_path
		} ]' \
	   "${POD_MANIFEST_DIR}/alpine-container.json" > "$container_json"

	local syscont=$(crictl_run $container_json ${POD_MANIFEST_DIR}/alpine-pod.json)
	local pod=$(crictl_cont_get_pod $syscont)

	# Verify the volume got mounted and it has the correct ownership
	run crictl exec $syscont cat "$ctr_path/testfile.txt"
	[ "$status" -eq 0 ]
	[[ "$output" == "some data" ]]

	uid=$(crictl exec $syscont stat -c '%u' $ctr_path)
	gid=$(crictl exec $syscont stat -c '%g' $ctr_path)

	[ $uid -eq 0 ]
	[ $gid -eq 0 ]

	# Verify shiftfs is mounted on the pod's volume
	run crictl exec $syscont sh -c "grep $ctr_path /proc/self/mountinfo | grep shiftfs"
	[ "$status" -eq 0 ]

	# Verify the pod can write to the mounted host volume
	run crictl exec $syscont sh -c "echo 'new data' > $ctr_path/testfile.txt"
	[ "$status" -eq 0 ]

	run crictl exec $syscont cat "$ctr_path/testfile.txt"
	[ "$status" -eq 0 ]
	[[ "$output" == "new data" ]]

	# Cleanup
	crictl stopp $pod
	crictl rmp $pod
	rm -rf $host_path
	rm -rf $container_json
}

@test "pod hostPath vol (read-only)" {

	# Create a dir on the host with ownership matching the sys container's root
	# process.
	local host_path=$(mktemp -d "${WORK_DIR}/tmp-vol.XXXXXX")
	echo "some data" > $host_path/testfile.txt

	subuid=$(grep containers /etc/subuid | cut -d":" -f2)
	subgid=$(grep containers /etc/subgid | cut -d":" -f2)
   chown -R $subuid:$subgid $host_path

	# Create a pod with a volume mount of that host dir
	local ctr_path="/mnt/test-vol"
	local container_json="${WORK_DIR}/container.json"

	jq --arg host_path "$host_path" --arg ctr_path "$ctr_path" \
		'  .mounts = [ {
   			host_path: $host_path,
	   		container_path: $ctr_path,
				readonly: true,
		} ]' \
	   "${POD_MANIFEST_DIR}/alpine-container.json" > "$container_json"

	local syscont=$(crictl_run $container_json ${POD_MANIFEST_DIR}/alpine-pod.json)
	local pod=$(crictl_cont_get_pod $syscont)

	# Verify the volume got mounted and it has the correct ownership
	run crictl exec $syscont cat "$ctr_path/testfile.txt"
	[ "$status" -eq 0 ]
	[[ "$output" == "some data" ]]

	uid=$(crictl exec $syscont stat -c '%u' $ctr_path)
	gid=$(crictl exec $syscont stat -c '%g' $ctr_path)

	[ $uid -eq 0 ]
	[ $gid -eq 0 ]

	# Verify the pod can't write to the read-only mounted host volume
	run crictl exec $syscont sh -c "echo 'new data' > $ctr_path/testfile.txt"
	[ "$status" -ne 0 ]
	[[ "$output" == *"Read-only file system"* ]]

	# Cleanup
	crictl stopp $pod
	crictl rmp $pod
	rm -rf $host_path
	rm -rf $container_json
}
