# Testing of handler for /sys/devices/virtual hierarchy.

load ../helpers/fs
load ../helpers/run
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
# "/sys/devices/virtual/net" path operations.
@test "/sys/devices/virtual/net" {

  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  # This should only shows the devices inside the container
  sv_runc exec syscont sh -c "ls /sys/devices/virtual/net"
  [ "$status" -eq 0 ]
  [[ "$output" == "lo" ]]

  # The /sys/class/net/ softlink should work fine
  sv_runc exec syscont sh -c "stat -L /sys/class/net/lo"
  [ "$status" -eq 0 ]
}
