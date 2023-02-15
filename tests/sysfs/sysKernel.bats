# Testing of handler for /sys/kernel hierarchy.

load ../helpers/fs
load ../helpers/run
load ../helpers/sysbox
load ../helpers/shell
load ../helpers/sysbox-health

# Container name.
SYSCONT_NAME=""

function setup() {
  setup_busybox
}

function teardown() {
  teardown_busybox syscont
  sysbox_log_check
}

# Verify proper operation of the Sys handler.
@test "/sys file ops" {

  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "ls -l /sys | awk '(NR>1)'"
  [ "$status" -eq 0 ]
  local outputList="${output}"
  echo "$outputList"

  local outputArray
  stringToArray "${outputList}" outputArray
  declare -p outputArray

  # Iterate through each listed node to ensure that both the emulated
  # and the non-emulated resources display the expected file attributes.
  for (( i=0; i<${#outputArray[@]}; i++ )); do
    # We can rule out "/sys/firmware" node coz even though its uid/gid matches
    # the container's root, this node is always mounted RO as part of a tmpfs
    # file-system.
    if ! $(echo "${outputArray[$i]}" | egrep -q "firmware"); then
      verify_owner "nobody" "nogroup" "${outputArray[$i]}"
    fi
  done
}

# Verifies the proper beahvior of the sysKernel handler for "/sys/kernel"
# path operations.
@test "/sys/kernel file ops" {

  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "ls -l /sys/kernel | awk '(NR>1)'"
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

    if echo ${outputArray[$i]} | egrep -q "config"; then
      verify_perm_owner "drwxr-xr-x" "root" "root" "${outputArray[$i]}"
    elif echo ${outputArray[$i]} | egrep -q "debug" ||
         echo ${outputArray[$i]} | egrep -q "tracing"; then
      verify_perm_owner "drwx------" "root" "root" "${outputArray[$i]}"
    else
      verify_owner "nobody" "nogroup" "${outputArray[$i]}"

      # sysKernel handler is expected to fetch node attrs directly from the
      # host fs for non-emulated resources. If that's the case, inodes for each
      # node should fully match.
      local hostInode=$(stat -c %i /sys/kernel/$node)

      sv_runc exec syscont sh -c "stat -c %i /sys/kernel/$node"
      [ "$status" -eq 0 ]
      local syscontInode="${output}"

      [[ "$hostInode" == "$syscontInode" ]]
    fi
  done

  # Verify that none of the emulated folders display any content (host
  # file).

  sv_runc exec syscont sh -c "ls -l /sys/kernel/config"
  [ "$status" -eq 0 ]
  local outputList="${output}"
  echo "$outputList"
  [[ "$outputList" == "total 0" ]]

  sv_runc exec syscont sh -c "ls -l /sys/kernel/debug"
  [ "$status" -eq 0 ]
  local outputList="${output}"
  echo "$outputList"
  [[ "$outputList" == "total 0" ]]

  sv_runc exec syscont sh -c "ls -l /sys/kernel/tracing"
  [ "$status" -eq 0 ]
  local outputList="${output}"
  echo "$outputList"
  [[ "$outputList" == "total 0" ]]
}

# Verify the proper operation of the sysKernel handler for non-emulated
# resources within an inner hierarchy (e.g., "/sys/kernel/mm/ksm").
@test "/sys/kernel/mm/ksm file ops" {

  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "ls -l /sys/kernel/mm/ksm | awk '(NR>1)'"
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

    # sysKernel handler is expected to fetch node attrs directly from the
    # host fs for non-emulated resources. If that's the case, inodes for each
    # node should fully match.

    run sh -c "stat -c %i /sys/kernel/mm/ksm/$node"
    [ "$status" -eq 0 ]
    local hostInode="$output"

    sv_runc exec syscont sh -c "stat -c %i /sys/kernel/mm/ksm/$node"
    [ "$status" -eq 0 ]
    local syscontInode="$output"

    [[ "$hostInode" == "$syscontInode" ]]

    # Verify that content outside and inside the container matches for
    # non-emulated nodes.

    run sh -c "cat /sys/kernel/mm/ksm/$node"
    [ "$status" -eq 0 ]
    local hostNodeContent="$output"

    sv_runc exec syscont sh -c "cat /sys/kernel/mm/ksm/$node"
    [ "$status" -eq 0 ]
    local syscontNodeContent="$output"

    [[ "$hostNodeContent" == "$syscontNodeContent" ]]

    # Verify that no regular (non-emulated) node is writable through this handler.
    sv_runc exec syscont sh -c "echo 1 > /sys/kernel/mm/ksm/$node"
    [ "$status" -ne 0 ]
    [[ "${output}" =~ "Permission denied" ]]
  done
}
