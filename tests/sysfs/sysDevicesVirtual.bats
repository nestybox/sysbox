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
