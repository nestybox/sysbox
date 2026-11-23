# Testing of handler for /sys/devices/virtual hierarchy.

load ../helpers/fs
load ../helpers/run
load ../helpers/docker
load ../helpers/sysbox
load ../helpers/shell
load ../helpers/environment
load ../helpers/sysbox-health

function setup() {
  setup_busybox
}

function teardown() {
  teardown_busybox syscont
  sysbox_log_check
}

# Verifies the proper behavior of the sysDevicesVirtual handler for
# "/sys/devices/virtual" path operations.
@test "/sys/devices/virtual file ops" {

  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "ls -l /sys/devices/virtual | awk '(NR>1)'"
  [ "$status" -eq 0 ]
  local outputList="${output}"
  echo "$outputList"

  local outputArray
  stringToArray "${outputList}" outputArray
  declare -p outputArray

  # Iterate through each listed node to ensure that both the emulated
  # and the non-emulated resources display the expected file attributes.
  for (( i=0; i<${#outputArray[@]}; i++ )); do
    local node=$(echo "${outputArray[i]}" | awk '{print $9}')

    if echo ${outputArray[$i]} | egrep -q "dmi"; then
      if [[ $(get_platform) == "arm64" ]]; then
        verify_perm_owner "drwxr-xr-x" "nobody" "nobody" "${outputArray[$i]}"
      else
        verify_perm_owner "drwxr-xr-x" "nobody" "nogroup" "${outputArray[$i]}"
      fi
    else
      if [[ $(get_platform) == "arm64" ]]; then
        verify_owner "nobody" "nobody" "${outputArray[$i]}"
      else
        verify_owner "nobody" "nogroup" "${outputArray[$i]}"
      fi

      # sysDevicesVirtual handler is expected to fetch node attrs from the
      # container for non-emulated resources. Since sysfs is a global
      # filessystem, inodes for each node should fully match those of the host.

      nodePath="/sys/devices/virtual/$node"
      hostInode=$(stat -c %i $nodePath)

      sv_runc exec syscont sh -c "stat -c %i $nodePath"
      [ "$status" -eq 0 ]
      local syscontInode="${output}"

      [[ "$hostInode" == "$syscontInode" ]]
    fi
  done
}

# Verifies the proper behavior of the sysDevicesVirtual handler for
# "/sys/devices/virtual/net" path operations. The handler is expected to enter
# the container namespaces to retrieve the list of network devices.
@test "/sys/devices/virtual/net file ops" {

	docker network rm testnet
	docker network create testnet
	[ "$status" -eq 0 ]

	local syscont=$(docker_run --rm --net=testnet ${CTR_IMG_REPO}/alpine:latest tail -f /dev/null)

	docker network connect bridge $syscont
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c "ls /sys/devices/virtual/net"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "eth0".+"eth1".+"lo" ]]

	for dev in eth0 eth1 lo; do
		docker exec "$syscont" sh -c "ls /sys/devices/virtual/net/${dev}/addr_len"
		[ "$status" -eq 0 ]

		docker exec "$syscont" sh -c "cat /sys/devices/virtual/net/${dev}/addr_len"
		[ "$status" -eq 0 ]
		[[ "$output" == "6" ]]

		# expected to fail with EPERM
		docker exec "$syscont" sh -c "echo 7 > /sys/devices/virtual/net/${dev}/addr_len"
		[ "$status" -eq 1 ]
	done

	docker_stop "$syscont"

	docker network rm testnet
}

# Verifies the proper behavior of the sysDevicesVirtual handler for
# soft-link nodes within the "/sys/devices/virtual/block" hierarchy.
@test "/sys/devices/virtual/block file ops softlink nodes" {

  if ! ls -l /sys/devices/virtual/block | egrep -q loop0; then
    skip "loop0 block is not present"
  fi

  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "ls -l /sys/devices/virtual/block/loop0 | egrep -q \"subsystem -> ../../../../class/block\""
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "stat /sys/devices/virtual/block/loop0/subsystem | egrep -q \"../../../../class/block\""
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "ls -l /sys/devices/virtual/block/loop0/subsystem | egrep -q \"/sys/devices/virtual/block/loop0/subsystem -> ../../../../class/block\""
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "ls -l /sys/devices/virtual/block/loop0/subsystem/ | egrep -q \"loop0 -> ../../devices/virtual/block/loop0\""
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "ls -l /sys/devices/virtual/block/loop0/subsystem/loop0/ | egrep -q \"subsystem -> ../../../../class/block\""
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "stat /sys/devices/virtual/block/loop0/subsystem/loop0/subsystem | egrep -q \"../../../../class/block\""
  [ "$status" -eq 0 ]
}

# Verifies the proper behavior of the sysDevicesVirtual handler for
# soft-link nodes within the "/sys/devices/virtual/net" hierarchy
# (passthrough nodes).
@test "/sys/devices/virtual/net file ops softlink nodes (passthrough)" {

  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "ls -l /sys/devices/virtual/net/lo | egrep -q \"subsystem -> ../../../../class/net\""
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "stat /sys/devices/virtual/net/lo/subsystem | egrep -q \"../../../../class/net\""
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "ls -l /sys/devices/virtual/net/lo/subsystem | egrep -q \"/sys/devices/virtual/net/lo/subsystem -> ../../../../class/net\""
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "ls -l /sys/devices/virtual/net/lo/subsystem/ | egrep -q \"lo -> ../../devices/virtual/net/lo\""
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "ls -l /sys/devices/virtual/net/lo/subsystem/lo/ | egrep -q \"subsystem -> ../../../../class/net\""
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "stat /sys/devices/virtual/net/lo/subsystem/lo/subsystem | egrep -q \"../../../../class/net\""
  [ "$status" -eq 0 ]
}

# Verifies the sysDevicesVirtual handler for the "/sys/devices/virtual/kfd"
# hierarchy. AMD ROCm (libhsakmt) enumerates GPUs by reading the topology nodes
# under it. The kernel gates reads of GPU-backed nodes on the device cgroup of
# the reader, so these tests check that a sys container gets what its device
# grants allow, and nothing more. Skipped unless the host has AMD KFD.
#
# Nesting: the kfd topology is not namespaced, and the only container context
# the kernel consults is the reader's device cgroup. Docker inside a sys
# container cannot attach device programs of its own, so the effective device
# policy of an inner container is that of the outer sys container. The inner
# container tests therefore compare against the outer container's own result,
# and do not assume that an inner container without grants is denied.

KFD_NODES="/sys/devices/virtual/kfd/kfd/topology/nodes"

function kfd_skip_without_kfd() {
  if [[ ! -e /sys/class/kfd/kfd || ! -e /dev/kfd ]]; then
    skip "AMD KFD not present on this host (needs /sys/class/kfd/kfd and /dev/kfd)"
  fi
}

# Prints the --device options that ROCm needs for the GPU.
function kfd_device_opts() {
  local opts="--device /dev/kfd"
  for dev in /dev/dri/renderD*; do
    [[ -e "$dev" ]] && opts+=" --device $dev"
  done
  echo "$opts"
}

# With the GPU devices granted, every topology node must read exactly as on the
# host, GPU nodes included.
@test "/sys/devices/virtual/kfd file ops with GPU devices (passthrough)" {

  kfd_skip_without_kfd

  local syscont
  syscont=$(docker run -d --runtime=sysbox-runc $(kfd_device_opts) --rm ${CTR_IMG_REPO}/alpine:latest tail -f /dev/null)
  [ "$?" -eq 0 ]

  for node in $(ls $KFD_NODES); do
    local props="$KFD_NODES/$node/properties"

    run docker exec "$syscont" sh -c "cat $props"
    [ "$status" -eq 0 ]
    [[ -n "$output" ]]
    [[ "$output" == "$(cat $props)" ]]

    run docker exec "$syscont" sh -c "cat $KFD_NODES/$node/gpu_id"
    [ "$status" -eq 0 ]
    [[ "$output" == "$(cat $KFD_NODES/$node/gpu_id)" ]]
  done

  docker_stop "$syscont"
}

# Without the GPU devices, the sys container must get the same outcome as a
# plain runc container for every topology node: GPU nodes are denied with
# EPERM, and the CPU node (not device-gated) is readable with the host content.
@test "/sys/devices/virtual/kfd file ops without GPU devices (mirrors runc)" {

  kfd_skip_without_kfd

  local runcCont
  runcCont=$(docker run -d --rm --runtime=runc ${CTR_IMG_REPO}/alpine:latest tail -f /dev/null)
  [ "$?" -eq 0 ]

  local syscont
  syscont=$(docker run -d --rm --runtime=sysbox-runc ${CTR_IMG_REPO}/alpine:latest tail -f /dev/null)
  [ "$?" -eq 0 ]

  for node in $(ls $KFD_NODES); do
    local props="$KFD_NODES/$node/properties"

    run docker exec "$runcCont" sh -c "cat $props"
    local runcStatus="$status"
    local runcOutput="$output"

    run docker exec "$syscont" sh -c "cat $props"
    [ "$status" -eq "$runcStatus" ]

    if [[ "$runcStatus" -eq 0 ]]; then
      # Readable under runc: must be readable here with the host's content.
      [[ "$output" == "$runcOutput" ]]
      [[ "$output" == "$(cat $props)" ]]
    else
      # Denied under runc: must be denied here with the same errno.
      [[ "$output" == *"Operation not permitted"* ]]
    fi
  done

  docker_stop "$syscont"
  docker_stop "$runcCont"
}

# Starts a sys container with the given device options, running dockerd inside
# it. Prints the container id.
function kfd_start_outer_with_docker() {
  local devOpts="$1"

  local outer
  outer=$(docker run -d --rm --runtime=sysbox-runc $devOpts ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  [ "$?" -eq 0 ]

  docker exec -d "$outer" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$?" -eq 0 ]

  wait_for_inner_dockerd "$outer"

  echo "$outer"
}

# An inner container granted the GPU devices (inside an outer sys container that
# is also granted them) must read exactly as the host, GPU nodes included.
@test "/sys/devices/virtual/kfd file ops in an inner container with GPU devices" {

  kfd_skip_without_kfd

  local outer
  outer=$(kfd_start_outer_with_docker "$(kfd_device_opts)")

  for node in $(ls $KFD_NODES); do
    local props="$KFD_NODES/$node/properties"

    run docker exec "$outer" sh -c "docker run --rm $(kfd_device_opts) ${CTR_IMG_REPO}/alpine:latest cat $props"
    [ "$status" -eq 0 ]
    [[ -n "$output" ]]
    [[ "$output" == "$(cat $props)" ]]
  done

  docker_stop "$outer"
}

# An inner container without the GPU devices, inside an outer sys container that
# is granted them, gets the outer container's result: the effective device
# policy is the outer container's, since Docker inside a sys container cannot
# attach its own device programs. The expectation is equality with the outer
# result, not EPERM.
@test "/sys/devices/virtual/kfd file ops in an inner container without GPU devices (outer granted)" {

  kfd_skip_without_kfd

  local outer
  outer=$(kfd_start_outer_with_docker "$(kfd_device_opts)")

  for node in $(ls $KFD_NODES); do
    local props="$KFD_NODES/$node/properties"

    run docker exec "$outer" sh -c "cat $props"
    [ "$status" -eq 0 ]
    local outerOutput="$output"

    run docker exec "$outer" sh -c "docker run --rm ${CTR_IMG_REPO}/alpine:latest cat $props"
    [ "$status" -eq 0 ]
    [[ "$output" == "$outerOutput" ]]
  done

  docker_stop "$outer"
}

# Same property with an outer sys container that is not granted the GPU: the
# inner container must match the outer container for every node, GPU nodes
# denied with EPERM and the CPU node readable.
@test "/sys/devices/virtual/kfd file ops in an inner container without GPU devices (outer not granted)" {

  kfd_skip_without_kfd

  local outer
  outer=$(kfd_start_outer_with_docker "")

  for node in $(ls $KFD_NODES); do
    local props="$KFD_NODES/$node/properties"

    run docker exec "$outer" sh -c "cat $props"
    local outerStatus="$status"
    local outerOutput="$output"

    run docker exec "$outer" sh -c "docker run --rm ${CTR_IMG_REPO}/alpine:latest cat $props"
    [ "$status" -eq "$outerStatus" ]

    if [[ "$outerStatus" -eq 0 ]]; then
      [[ "$output" == "$outerOutput" ]]
    else
      [[ "$output" == *"Operation not permitted"* ]]
    fi
  done

  docker_stop "$outer"
}
