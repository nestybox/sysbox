# Testing of handler for /sys/devices/virtual/dmi hierarchy.

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

# Verifies the proper behavior of the sysDevicesVirtualDmi handler for
# "/sys/devices/virtual/dmi" path operations.
@test "/sys/devices/virtual/dmi file ops" {

  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "ls -l /sys/devices/virtual/dmi | awk '(NR>1)'"
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

    if echo ${outputArray[$i]} | egrep -q "id"; then
      if [[ $(get_platform) == "arm64" ]]; then
        verify_perm_owner "drwxr-xr-x" "nobody" "nobody" "${outputArray[$i]}"
      else
        verify_perm_owner "drwxr-xr-x" "nobody" "nogroup" "${outputArray[$i]}"
      fi
    else
      # Currently, no other file/dir is expected in this path, but i'm leaving
      # this checkmark here just in case new sysfs nodes are exposed by in the
      # future.

      if [[ $(get_platform) == "arm64" ]]; then
        verify_owner "nobody" "nobody" "${outputArray[$i]}"
      else
        verify_owner "nobody" "nogroup" "${outputArray[$i]}"
      fi

      # sysDevicesVirtualDmi handler is expected to fetch node attrs directly
      # from the host fs for non-emulated resources. If that's the case, inodes
      # for each node should fully match.

      nodePath="/sys/devices/virtual/dmi/$node"
      hostInode=$(stat -c %i $nodePath)

      sv_runc exec syscont sh -c "stat -c %i $nodePath"
      [ "$status" -eq 0 ]
      local syscontInode="${output}"

      [[ "$hostInode" == "$syscontInode" ]]
    fi
  done
}
