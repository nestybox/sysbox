# Testing of handler for /sys/devices/virtual/dmi/id hierarchy.

load ../helpers/fs
load ../helpers/run
load ../helpers/sysbox
load ../helpers/sysbox-health

# Container name.
SYSCONT_NAME=""

# Default cap_last_cap value in host fs.
SYS_DMI_PRODUCT_UUID_DEFAULT_VAL=""

function setup() {
  setup_busybox

  # Define default cap_last_cap value to utilize during testing.
  run cat /sys/devices/virtual/dmi/id/product_uuid
  [ "$status" -eq 0 ]
  # Skip the last 12 characters of the product_uuid as it will differ between the
  # host and the sys containers. Refer to "sysDevicesVirtualDmiId.go" for details.
  SYS_DMI_PRODUCT_UUID_DEFAULT_VAL=${output::-12}
}

function teardown() {
  teardown_busybox syscont
  sysbox_log_check
}

function stringToArray() {
  local str="$1"
  local -n arr="$2"

  SAVEIFS=$IFS       # Save current IFS
  IFS=$'\n'          # Change IFS to newline char
  arr=($str)         # split the `str` string into an array
  IFS=$SAVEIFS       # Restore original IFS
}

# Verifies the proper beahvior of the sysDevicesVirtualDmiId handler for
# "/sys/devices/virtual/dmi/id" path operations.
@test "/sys/devices/virtual/dmi/id file ops" {

  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "ls -l /sys/devices/virtual/dmi/id | awk '(NR>1)'"
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

    if echo ${outputArray[$i]} | egrep -q "product_uuid"; then
      verify_perm_owner "-r--------" "root" "root" "${outputArray[$i]}"

    else
      verify_owner "nobody" "nogroup" "${outputArray[$i]}"

      # sysDevicesVirtualDmiId handler is expected to fetch node attrs directly
      # from the host fs for non-emulated resources. If that's the case, inodes
      # for each node should fully match.
      #
      # Also, notice that there could be symlinks in this hierarchy, so we must
      # resolve them before proceeding.
      if [[ -L "/sys/devices/virtual/dmi/id/$node" ]]; then
        nodePath=$(readlink -f /sys/devices/virtual/dmi/id/$node)
      else
        nodePath="/sys/devices/virtual/dmi/id/$node"
      fi

      hostInode=$(stat -c %i $nodePath)

      sv_runc exec syscont sh -c "stat -c %i $nodePath"
      [ "$status" -eq 0 ]
      local syscontInode="${output}"

      [[ "$hostInode" == "$syscontInode" ]]
    fi
  done
}

# Verify the proper operation of the sysKernel handler for non-emulated
# resources within an inner hierarchy (e.g., "/sys/kernel/mm/ksm").
@test "/sys/devices/virtual/dmi/id/power file ops" {

  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "ls -l /sys/devices/virtual/dmi/id/power | awk '(NR>1)'"
  [ "$status" -eq 0 ]
  local outputList="${output}"
  echo "$outputList"

  local outputArray
  stringToArray "${outputList}" outputArray
  declare -p outputArray

  # Iterate through each listed node to ensure that all the resources match
  # the expected file attributes.
  for (( i=0; i<${#outputArray[@]}; i++ )); do
    local node=$(echo "${outputArray[i]}" | awk '{print $9}')

    verify_owner "nobody" "nogroup" "${outputArray[$i]}"

    # Looks like there's a kernel bug preventing this sysfs node from being
    # read (failure occurs at host level too), so let's skip it here.
    [[ $node == "autosuspend_delay_ms" ]] && continue

    # sysKernel handler is expected to fetch node attrs directly from the
    # host fs for non-emulated resources. If that's the case, inodes for each
    # node should fully match.

    run sh -c "stat -c %i /sys/devices/virtual/dmi/id/power/$node"
    [ "$status" -eq 0 ]
    local hostInode="$output"

    sv_runc exec syscont sh -c "stat -c %i /sys/devices/virtual/dmi/id/power/$node"
    [ "$status" -eq 0 ]
    local syscontInode="$output"

    [[ "$hostInode" == "$syscontInode" ]]

    # Verify that content outside and inside the container matches for
    # non-emulated nodes.

    run sh -c "cat /sys/devices/virtual/dmi/id/power/$node"
    [ "$status" -eq 0 ]
    local hostNodeContent="$output"

    sv_runc exec syscont sh -c "cat /sys/devices/virtual/dmi/id/power/$node"
    [ "$status" -eq 0 ]
    local syscontNodeContent="$output"

    [[ "$hostNodeContent" == "$syscontNodeContent" ]]

    # Verify that no regular (non-emulated) node is writable through this handler.
    sv_runc exec syscont sh -c "echo 1 > /sys/devices/virtual/dmi/id/power/$node"
    [ "$status" -ne 0 ]
    [[ "${output}" =~ "Permission denied" ]]
  done
}

# Verify file-ops specifically for "/sys/devices/virtual/dmi/id/product_uuid"
# node.
@test "/sys/devices/virtual/dmi/id/product_uuid operations" {

  # Check getattr() op

  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c \
    "ls -lrt /sys/devices/virtual/dmi/id/product_uuid"
  [ "$status" -eq 0 ]

  verify_perm_owner "-r--------" "root" "root" "${output}"

  # Check read() op

  sv_runc exec syscont sh -c \
    "cat /sys/devices/virtual/dmi/id/product_uuid"
  [ "$status" -eq 0 ]

  # Read value should match the first 25 chars of the existing host-fs
  # figure.
  [[ "$output" =~ $SYS_DMI_PRODUCT_UUID_DEFAULT_VAL ]]

  # Check write() op

  sv_runc exec syscont sh -c \
    "echo 1 > /sys/devices/virtual/dmi/id/product_uuid"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Permission denied" ]]

  # Read value back and verify that it's matching the original one.
  sv_runc exec syscont sh -c \
    "cat /sys/devices/virtual/dmi/id/product_uuid"
  [ "$status" -eq 0 ]
  [[ "$output" =~ $SYS_DMI_PRODUCT_UUID_DEFAULT_VAL ]]

  # Read from host-fs and verify that its value hasn't been modified.
  run cat /sys/devices/virtual/dmi/id/product_uuid
  [ "$status" -eq 0 ]
  [[ "$output" =~ $SYS_DMI_PRODUCT_UUID_DEFAULT_VAL ]]
}

