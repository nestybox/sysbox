#!/usr/bin/env bats

#
# Verify trapping & emulation on "mount" and "unmount2" syscalls
#

load ../../helpers/run
load ../../helpers/syscall
load ../../helpers/docker
load ../../helpers/environment
load ../../helpers/mounts
load ../../helpers/sysbox
load ../../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

# Test to verify immutable mounts within a sys container's unshare(mnt) context.
#
# Note: a sys container immutable mount is a mount that is setup at container
# creation time.
#

# Testcase #1.
#
# Ensure immutable mounts can't be unmounted from inside an inner mount
# namespace if, and only if, sysbox-fs is running with
# 'allow-immutable-unmounts' option disabled. Alternatively, verify that
# unmounts are always allowed.
@test "immutable mount can't be unmounted -- unshare(mnt)" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)

  docker exec -d ${syscont} sh -c "unshare -m bash -c \"sleep 1000\""
  [ "$status" -eq 0 ]

  docker exec ${syscont} sh -c "pidof sleep"
  [ "$status" -eq 0 ]
  local inner_pid=$output

  local immutable_mounts=$(list_container_mounts ${syscont} ${inner_pid} "/")
  run is_list_empty ${immutable_mounts}
  [ "$status" -ne 0 ]

  # Determine the mode in which to operate.
  local unmounts_allowed
  run allow_immutable_unmounts
  if [ "${status}" -eq 0 ]; then
    unmounts_allowed=0
  else
    unmounts_allowed=1
  fi

  for m in $immutable_mounts; do
    # Skip /proc and /sys since these are special mounts (we have dedicated
    # tests that cover unmounting ops).
    if [[ ${m} =~ "/proc" ]] || [[ ${m} =~ "/proc/*" ]] ||
        [[ ${m} =~ "/sys" ]] || [[ ${m} =~ "/sys/*" ]] ||
        [[ ${m} =~ "/dev" ]] || [[ ${m} =~ "/dev/*" ]]; then
        continue
    fi

    printf "\ntesting unmount of immutable mount ${m}\n"

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} umount ${m}"
    if [[ ${unmounts_allowed} -eq 0 ]]; then
      [ "$status" -eq 0 ]
    else
      [ "$status" -ne 0 ]
    fi
  done

  local immutable_mounts_after=$(list_container_mounts ${syscont} ${inner_pid} "/")
  if [[ ${unmounts_allowed} -eq 0 ]]; then
    [[ ${immutable_mounts} != ${immutable_mounts_after} ]]
  else
    [[ ${immutable_mounts} == ${immutable_mounts_after} ]]
  fi

  docker_stop ${syscont}
}

# Testcase #2.
#
# Ensure that a read-only immutable mount can't be remounted as read-write
# inside an inner mount namespace if, and only if, sysbox-fs is running with
# 'allow-immutable-remounts' option disabled. Alternatively, verify that
# remounts are allowed.
@test "immutable ro mount can't be remounted rw -- unshare(mnt)" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)

  docker exec -d ${syscont} sh -c "unshare -m bash -c \"sleep 1000\""
  [ "$status" -eq 0 ]

  docker exec ${syscont} sh -c "pidof sleep"
  [ "$status" -eq 0 ]
  local inner_pid=$output

  local immutable_ro_mounts=$(list_container_ro_mounts ${syscont} ${inner_pid} "/")
  run is_list_empty ${immutable_ro_mounts}
  [ "$status" -ne 0 ]

  # Determine the mode in which to operate.
  local remounts_allowed
  run allow_immutable_remounts
  if [ "${status}" -eq 0 ]; then
    remounts_allowed=0
  else
    remounts_allowed=1
  fi

  for m in ${immutable_ro_mounts}; do
    printf "\ntesting rw remount of immutable ro mount ${m}\n"

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} mount -o remount,bind,rw ${m}"
    if [[ ${remounts_allowed} -eq 0 ]]; then
      [ "$status" -eq 0 ]
    else
      [ "$status" -ne 0 ]
    fi
  done

  local immutable_ro_mounts_after=$(list_container_ro_mounts ${syscont} ${inner_pid} "/")
  if [[ ${remounts_allowed} -eq 0 ]]; then
    [[ ${immutable_ro_mounts} != ${immutable_ro_mounts_after} ]]
  else
    [[ ${immutable_ro_mounts} == ${immutable_ro_mounts_after} ]]
  fi

  docker_stop ${syscont}
}

# Testcase #3.
#
# Ensure that a read-write immutable mount *can* be remounted as read-only inside
# an inner mount namespace, and then back to read-write.
@test "immutable rw mount can be remounted ro -- unshare(mnt)" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)

  docker exec -d ${syscont} sh -c "unshare -m bash -c \"sleep 1000\""
  [ "$status" -eq 0 ]

  docker exec ${syscont} sh -c "pidof sleep"
  [ "$status" -eq 0 ]
  local inner_pid=$output

  local immutable_rw_mounts=$(list_container_rw_mounts ${syscont} ${inner_pid} "/")
  run is_list_empty ${immutable_rw_mounts}
  [ "$status" -ne 0 ]

  for m in ${immutable_rw_mounts}; do

    # Remounting /proc or /dev as read-only will prevent docker execs into the
    # container; skip these.
    if [[ ${m} =~ "/proc" ]] || [[ ${m} =~ "/proc/*" ]] ||
       [[ ${m} =~ "/dev" ]] || [[ ${m} =~ "/dev/*" ]]; then
      continue
    fi

    printf "\ntesting ro remount of immutable rw mount ${m}\n"

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} mount -o remount,bind,ro ${m}"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} mount -o remount,bind,rw ${m}"
    [ "$status" -eq 0 ]
  done

  docker_stop ${syscont}
}

# Testcase #4.
#
# Ensure that a read-only immutable mount *can* be remounted as read-only inside
# an inner mount namespace.
@test "immutable ro mount can be remounted ro -- unshare(mnt)" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)

  docker exec -d ${syscont} sh -c "unshare -m bash -c \"sleep 1000\""
  [ "$status" -eq 0 ]

  docker exec ${syscont} sh -c "pidof sleep"
  [ "$status" -eq 0 ]
  local inner_pid=$output

  local immutable_ro_mounts=$(list_container_ro_mounts ${syscont} ${inner_pid} "/")
  run is_list_empty ${immutable_ro_mounts}
  [ "$status" -ne 0 ]

  for m in ${immutable_ro_mounts}; do
    printf "\ntesting ro remount of immutable ro mount ${m}\n"

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} mount -o remount,bind,ro ${m}"
    [ "$status" -eq 0 ]
  done

  local immutable_ro_mounts_after=$(list_container_ro_mounts ${syscont} ${inner_pid} "/")
  [[ ${immutable_ro_mounts} == ${immutable_ro_mounts_after} ]]

  docker_stop ${syscont}
}

# Testcase #5.
#
# Ensure that a read-write immutable mount *can* be remounted as read-write
# inside an inner mount namespace.
@test "immutable rw mount can be remounted rw -- unshare(mnt)" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)

  docker exec -d ${syscont} sh -c "unshare -m bash -c \"sleep 1000\""
  [ "$status" -eq 0 ]

  docker exec ${syscont} sh -c "pidof sleep"
  [ "$status" -eq 0 ]
  local inner_pid=$output

  local immutable_rw_mounts=$(list_container_rw_mounts ${syscont} ${inner_pid} "/")
  run is_list_empty ${immutable_rw_mounts}
  [ "$status" -ne 0 ]

  for m in ${immutable_rw_mounts}; do
    printf "\ntesting rw remount of immutable rw mount ${m}\n"

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} mount -o remount,bind,rw ${m}"
    [ "$status" -eq 0 ]
  done

  local immutable_rw_mounts_after=$(list_container_rw_mounts ${syscont} ${inner_pid} "/")
  [[ ${immutable_rw_mounts} == ${immutable_rw_mounts_after} ]]

  docker_stop ${syscont}
}

# Testcase #6.
#
# Within an inner mount namespace, ensure that a read-only immutable mount can
# be bind-mounted to a new mountpoint, but not re-mounted read-write at the new
# mountpoint if, and only if, sysbox-fs is running with 'allow-immutable-remounts'
# knob disabled. Otherwise, allow remounts to succeed.
@test "immutable ro mount can't be bind-mounted rw -- unshare(mnt)" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)

  docker exec -d ${syscont} sh -c "unshare -m bash -c \"sleep 1000\""
  [ "$status" -eq 0 ]

  docker exec ${syscont} sh -c "pidof sleep"
  [ "$status" -eq 0 ]
  local inner_pid=$output

  local immutable_ro_mounts=$(list_container_ro_mounts ${syscont} ${inner_pid} "/")
  run is_list_empty ${immutable_ro_mounts}
  [ "$status" -ne 0 ]
  local target=/root/target

  # Determine the mode in which to operate.
  local remounts_allowed
  run allow_immutable_remounts
  if [ "${status}" -eq 0 ]; then
    remounts_allowed=0
  else
    remounts_allowed=1
  fi

  for m in ${immutable_ro_mounts}; do

    printf "\ntesting bind-mount of immutable ro mount ${m}\n"

    # Create bind-mount target (dir or file, depending on bind-mount source type)
    docker exec ${syscont} bash -c "[[ -d ${m} ]]"

    if [ "$status" -eq 0 ]; then
      docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} mkdir -p ${target}"
      [ "$status" -eq 0 ]
    else
      docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} touch ${target}"
      [ "$status" -eq 0 ]
    fi

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} mount --bind ${m} ${target}"
    [ "$status" -eq 0 ]

    # Verify the bind-mount continues to be read-only
    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} touch ${target}"
    [ "$status" -ne 0 ]

    # This rw remount should fail if 'allow-immutable-remounts' knob is disabled
    # (default behavior).
    printf "\ntesting rw remount of immutable ro bind-mount ${target}\n"
    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} mount -o remount,bind,rw ${target}"
    if [[ ${remounts_allowed} -eq 0 ]]; then
      [ "$status" -eq 0 ]
    else
      [ "$status" -ne 0 ]
    fi

    # This ro remount should pass (it's not needed but just to double-check)
    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} mount -o remount,bind,ro ${target}"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} umount ${target}"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} rm -rf ${target}"
    [ "$status" -eq 0 ]
  done

  docker_stop ${syscont}
}

# Testcase #7.
#
# Within an inner mount namespace, ensure that a read-write immutable mount can
# be bind-mounted to a new mountpoint, then re-mounted read-only.
@test "immutable rw mount can be bind-mounted ro -- unshare(mnt)" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)

  docker exec -d ${syscont} sh -c "unshare -m bash -c \"sleep 1000\""
  [ "$status" -eq 0 ]

  docker exec ${syscont} sh -c "pidof sleep"
  [ "$status" -eq 0 ]
  local inner_pid=$output

  local immutable_rw_mounts=$(list_container_rw_mounts ${syscont} ${inner_pid} "/")
  run is_list_empty ${immutable_rw_mounts}
  [ "$status" -ne 0 ]
  local target=/root/target

  for m in ${immutable_rw_mounts}; do

    # skip /proc and /sys since these are special mounts (we have dedicated
    # tests for remounting them). We also
    if [[ ${m} =~ "/proc" ]] || [[ ${m} =~ "/proc/*" ]] ||
       [[ ${m} =~ "/sys" ]] || [[ ${m} =~ "/sys/*" ]] ||
       [[ ${m} =~ "/dev" ]] || [[ ${m} =~ "/dev/*" ]]; then
      continue
    fi

    printf "\ntesting bind-mount of immutable rw mount ${m}\n"

    # Create bind-mount target (dir or file, depending on bind-mount source type)
    docker exec ${syscont} bash -c "[[ -d ${m} ]]"

    if [ "$status" -eq 0 ]; then
      docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} mkdir -p ${target}"
      [ "$status" -eq 0 ]
    else
      docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} touch ${target}"
      [ "$status" -eq 0 ]
    fi

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} mount --bind ${m} ${target}"
    [ "$status" -eq 0 ]

    # Verify the bind-mount continues to be read-write
    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} touch ${target}"
    [ "$status" -eq 0 ]

    # This ro remount should pass
    printf "\ntesting ro remount of immutable rw bind-mount ${target}\n"
    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} mount -o remount,bind,ro ${target}"
    [ "$status" -eq 0 ]

    # Verify the bind-mount is now read-only
    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} touch ${target}"
    [ "$status" -ne 0 ]

    # Verify the bind-mount source continues to be read-write
    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} touch ${m}"
    [ "$status" -eq 0 ]

    # This rw remount should also pass
    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} mount -o remount,bind,rw ${target}"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} umount ${target}"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} rm -rf ${target}"
    [ "$status" -eq 0 ]
  done

  docker_stop ${syscont}
}

# Testcase #8.
#
# Within an inner mount namespace, ensure that a read-only immutable mount
# *can* be masked by a new read-write mount on top of it.
@test "rw mount on top of immutable ro mount -- unshare(mnt)" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)

  docker exec -d ${syscont} sh -c "unshare -m bash -c \"sleep 1000\""
  [ "$status" -eq 0 ]

  docker exec ${syscont} sh -c "pidof sleep"
  [ "$status" -eq 0 ]
  local inner_pid=$output

  local immutable_ro_mounts=$(list_container_ro_mounts ${syscont} ${inner_pid} "/")
  run is_list_empty ${immutable_ro_mounts}
  [ "$status" -ne 0 ]

  for m in ${immutable_ro_mounts}; do

    # skip /proc and /sys since these are special mounts (we have dedicated
    # tests for remounting them). We also
    if [[ ${m} =~ "/proc" ]] || [[ ${m} =~ "/proc/*" ]] ||
         [[ ${m} =~ "/sys" ]] || [[ ${m} =~ "/sys/*" ]] ||
         [[ ${m} =~ "/dev" ]] || [[ ${m} =~ "/dev/*" ]]; then
      continue
    fi

    # This should fail (mount is read-only)
    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} touch ${m}"
    [ "$status" -ne 0 ]

    printf "\nmounting tmpfs (rw) on top of immutable ro mount ${m}\n"

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} mount -t tmpfs -o size=100M tmpfs ${m}"
    [ "$status" -eq 0 ]

    # This should pass (tmpfs mount is read-write)
    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} touch ${m}"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} umount ${m}"
    [ "$status" -eq 0 ]

    # This should fail (mount is read-only)
    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} touch ${m}"
    [ "$status" -ne 0 ]
  done

  docker_stop ${syscont}
}

# Testcase #9.
#
# Within an inner mount namespace, ensure that a read-write immutable mount
# *can* be masked by a new read-only mount on top of it.
@test "ro mount on top of immutable rw mount -- unshare(mnt)" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)

  docker exec -d ${syscont} sh -c "unshare -m bash -c \"sleep 1000\""
  [ "$status" -eq 0 ]

  docker exec ${syscont} sh -c "pidof sleep"
  [ "$status" -eq 0 ]
  local inner_pid=$output

  local immutable_rw_mounts=$(list_container_rw_mounts ${syscont} ${inner_pid} "/")
  run is_list_empty ${immutable_rw_mounts}
  [ "$status" -ne 0 ]

  for m in ${immutable_rw_mounts}; do

    # skip /proc and /sys since these are special mounts (we have dedicated
    # tests for remounting them). We also
    if [[ ${m} =~ "/proc" ]] || [[ ${m} =~ "/proc/*" ]] ||
         [[ ${m} =~ "/sys" ]] || [[ ${m} =~ "/sys/*" ]] ||
         [[ ${m} =~ "/dev" ]] || [[ ${m} =~ "/dev/*" ]]; then
      continue
    fi

    # Skip file mountpoints.
    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} bash -c \"[[ ! -d ${m} ]]\""
    if [ "$status" -eq 0 ]; then
      continue
    fi

    # This should pass (mount is read-write)
    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} touch ${m}"
    [ "$status" -eq 0 ]

    printf "\nmounting tmpfs (ro) on top of immutable rw mount ${m}\n"

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} mount -t tmpfs -o ro,size=100M tmpfs ${m}"
    [ "$status" -eq 0 ]

    # This should fail (tmpfs mount is read-only)
    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} touch ${m}"
    [ "$status" -ne 0 ]

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} umount ${m}"
    [ "$status" -eq 0 ]

    # This should pass (mount is read-write)
    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} touch ${m}"
    [ "$status" -eq 0 ]
  done

  docker_stop ${syscont}
}

# Testcase #10.
#
# Ensure proper execution of unmount ops over mount-stacks and bind-mount chains
# formed by regular files mountpoints.
@test "unmount chain of file bind-mounts -- unshare(mnt)" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)

  docker exec -d ${syscont} sh -c "unshare -m bash -c \"sleep 1000\""
  [ "$status" -eq 0 ]

  docker exec ${syscont} sh -c "pidof sleep"
  [ "$status" -eq 0 ]
  local inner_pid=$output

  local immutable_mounts=$(list_container_mounts ${syscont} ${inner_pid} "/")
  run is_list_empty ${immutable_mounts}
  [ "$status" -ne 0 ]

  # Determine the mode in which to operate.
  local unmounts_allowed
  run allow_immutable_unmounts
  if [ "${status}" -eq 0 ]; then
    unmounts_allowed=0
  else
    unmounts_allowed=1
  fi

  for m in ${immutable_file_mounts}; do
    # Skip /proc and /sys since these are special mounts (we have dedicated
    # tests that cover unmounting ops).
    if [[ ${m} =~ "/proc" ]] || [[ ${m} =~ "/proc/*" ]] ||
        [[ ${m} =~ "/sys" ]] || [[ ${m} =~ "/sys/*" ]]; then
      continue
    fi

    # Skip non-file mountpoints.
    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} bash -c \"[[ ! -f ${m} ]]\""
    if [ "$status" -eq 0 ]; then
      continue
    fi

    # Create mount-stack and verify that the last element can be always
    # unmounted.
    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} mount -o bind /dev/null ${m}"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} umount ${m}"
    [ "$status" -eq 0 ]

    # Create bind-mount chain and verify the proper behavior of the unmount
    # operations attending to sysbox-fs runtime settings.
    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} touch ${m}2"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} mount -o bind ${m} ${m}2"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} umount ${m}2"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} umount ${m}"
    if [[ ${unmounts_allowed} -eq 0 ]]; then
      [ "$status" -eq 0 ]
    else
      [ "$status" -ne 0 ]
    fi

  done

  docker_stop ${syscont}
}

# Testcase #11.
#
# Ensure proper execution of unmount ops over mount-stacks and bind-mount chains
# formed by character-file mountpoints.
@test "umount chain of char bind-mounts -- unshare(mnt)" {

  local syscont=$(docker_run --rm -v /dev/null:/usr/bin/dpkg-maintscript-helper ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)

  docker exec -d ${syscont} sh -c "unshare -m bash -c \"sleep 1000\""
  [ "$status" -eq 0 ]

  docker exec ${syscont} sh -c "pidof sleep"
  [ "$status" -eq 0 ]
  local inner_pid=$output

  local immutable_mounts=$(list_container_mounts ${syscont} ${inner_pid} "/")
  run is_list_empty ${immutable_mounts}
  [ "$status" -ne 0 ]

  # Determine the mode in which to operate.
  local unmounts_allowed
  run allow_immutable_unmounts
  if [ "${status}" -eq 0 ]; then
    unmounts_allowed=0
  else
    unmounts_allowed=1
  fi

  for m in ${immutable_mounts}; do
    # Skip /proc and /sys since these are special mounts (we have dedicated
    # tests that cover unmounting ops).
    if [[ ${m} =~ "/proc" ]] || [[ ${m} =~ "/proc/*" ]] ||
        [[ ${m} =~ "/sys" ]] || [[ ${m} =~ "/sys/*" ]]; then
      continue
    fi

    # Skip non-char mountpoints.
    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} bash -c \"[[ ! -c ${m} ]]\""
    if [ "$status" -eq 0 ]; then
      continue
    fi

    # Create mount-stack and verify that last element can be always
    # unmounted.
    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} mount -o bind /dev/null ${m}"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} umount ${m}"
    [ "$status" -eq 0 ]

    # Create  bind-mount chain and verify the proper behavior of the unmount
    # operations attending to sysbox-fs runtime settings.
    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} touch ${m}2"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} mount -o bind ${m} ${m}2"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} umount ${m}2"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} umount ${m}"
    if [[ ${unmounts_allowed} -eq 0 ]]; then
      [ "$status" -eq 0 ]
    else
      [ "$status" -ne 0 ]
    fi

  done

  docker_stop ${syscont}
}

# Testcase #12.
#
# Ensure proper execution of unmount ops over mount-stacks and bind-mount chains
# formed by directory mountpoints.
@test "unmount chain of dir bind-mounts" {

  local syscont=$(docker_run --rm --mount type=tmpfs,destination=/app ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)

  docker exec -d ${syscont} sh -c "unshare -m bash -c \"sleep 1000\""
  [ "$status" -eq 0 ]

  docker exec ${syscont} sh -c "pidof sleep"
  [ "$status" -eq 0 ]
  local inner_pid=$output

  local immutable_mounts=$(list_container_mounts ${syscont} ${inner_pid} "/")
  run is_list_empty ${immutable_mounts}
  [ "$status" -ne 0 ]

  # Determine the mode in which to operate.
  local unmounts_allowed
  run allow_immutable_unmounts
  if [ "${status}" -eq 0 ]; then
    unmounts_allowed=0
  else
    unmounts_allowed=1
  fi

  for m in ${immutable_mounts}; do
    # Skip /proc and /sys since these are special mounts (we have dedicated
    # tests that cover unmounting ops).
    if [[ ${m} =~ "/proc" ]] || [[ ${m} =~ "/proc/*" ]] ||
        [[ ${m} =~ "/sys" ]] || [[ ${m} =~ "/sys/*" ]] ||
        [[ ${m} =~ "/dev" ]] || [[ ${m} =~ "/dev/*" ]]; then
      continue
    fi

    # Skip non-dir mountpoints.
    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} bash -c \"[[ ! -d ${m} ]]\""
    if [ "$status" -eq 0 ]; then
      continue
    fi

    # Create mount-stack and verify that last two elements can be always
    # unmounted.
    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} mount -t tmpfs -o ro,size=100M tmpfs ${m}"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} mount -t tmpfs -o ro,size=100M tmpfs ${m}"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} umount ${m}"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} umount ${m}"
    [ "$status" -eq 0 ]

    # Create bind-mount chain and verify the proper behavior of the unmount
    # operations attending to sysbox-fs runtime settings.
    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} mkdir ${m}2 ${m}3"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} mount -o bind ${m} ${m}2"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} mount -o bind ${m}2 ${m}3"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} umount ${m}3"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} umount ${m}2"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} umount ${m}"
    if [[ ${unmounts_allowed} -eq 0 ]]; then
      [ "$status" -eq 0 ]
    else
      [ "$status" -ne 0 ]
    fi
  done

  docker_stop ${syscont}
}

# Testcases #13-15.
#
# sysbox's kernel-header and kernel-module mounts (/usr/src/*,
# /lib/modules/<kernel>) are the only immutable mounts whose read-only
# attribute is enforced by the kernel itself (via MNT_LOCK_READONLY, set up
# by sysbox-mgr) rather than by sysbox-fs's own mount(2)/umount2(2) syscall
# mediation. See tests/syscall/mount/mount-immutables.bats for background;
# these testcases verify the protection also holds from within an inner
# mount namespace (unshare(mnt)), i.e. that a container process can't shed
# the kernel lock by giving itself a private copy of the mount table. They
# target *only* the kernel-header/module mounts, unlike the general
# "immutable ro mount can't be remounted rw" testcase above: other
# immutable mounts are not kernel-locked and would not survive a
# mount_setattr(2) attempt.

# Testcase #13.
#
# Build the mount-setattr-test helper binary; it issues mount_setattr(2)
# directly, bypassing sysbox-fs's mount(2)/umount2(2) syscall mediation
# entirely.
@test "mount-setattr-test prep -- unshare(mnt)" {
  pushd tests/syscall/mount/mount-setattr-test
  make
  popd
}

# Testcase #14.
#
# Ensure that, from within an inner mount namespace, a kernel header/module
# mount can't have its read-only attribute cleared via mount_setattr(2).
# Unlike the legacy mount(2) remount path (mediated by sysbox-fs, and
# gated by its 'allow-immutable-remounts' knob), this protection comes
# from a kernel guarantee (MNT_LOCK_READONLY) that sysbox-mgr sets up
# when anchoring the mount, and holds unconditionally -- sysbox-mgr has
# no 'allow-immutable-remounts' knob of its own to gate it with.
@test "kernel header/module mounts can't be unlocked via mount_setattr(2) -- unshare(mnt)" {

  local syscont=$(docker_run --rm \
    -v ${SYSBOX_ROOT}/tests/syscall/mount/mount-setattr-test:/mnt/mount-setattr-test \
    ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)

  local test_bin=/mnt/mount-setattr-test/mount-setattr-test

  docker exec ${syscont} sh -c "[ -x ${test_bin} ]"
  [ "$status" -eq 0 ]

  docker exec -d ${syscont} sh -c "unshare -m bash -c \"sleep 1000\""
  [ "$status" -eq 0 ]

  docker exec ${syscont} sh -c "pidof sleep"
  [ "$status" -eq 0 ]
  local inner_pid=$output

  local kernel_rel=$(__docker exec ${syscont} sh -c "uname -r")
  local immutable_ro_mounts=$(list_container_ro_mounts ${syscont} ${inner_pid} "/")

  local targets=()
  if grep -qxF "/usr/lib/modules/${kernel_rel}" <<< "${immutable_ro_mounts}"; then
    targets+=("/usr/lib/modules/${kernel_rel}")
  fi
  for m in ${immutable_ro_mounts}; do
    if [[ ${m} == "/usr/src/"* ]]; then
      targets+=("${m}")
    fi
  done

  if [ ${#targets[@]} -eq 0 ]; then
    docker_stop ${syscont}
    skip "no kernel header/module mounts present in this container"
  fi

  for m in "${targets[@]}"; do
    printf "\ntesting mount_setattr(2) clear of read-only on ${m}\n"

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} ${test_bin} ${m}"
    [ "$status" -ne 0 ]

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} touch ${m}/canary"
    [ "$status" -ne 0 ]
  done

  docker_stop ${syscont}
}

# Testcase #15.
#
# Same as above, but targeting a bind-mount of the kernel header/module
# mount rather than the mount itself.
@test "bind-mount of kernel header/module mount can't be unlocked via mount_setattr(2) -- unshare(mnt)" {

  local syscont=$(docker_run --rm \
    -v ${SYSBOX_ROOT}/tests/syscall/mount/mount-setattr-test:/mnt/mount-setattr-test \
    ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)

  local test_bin=/mnt/mount-setattr-test/mount-setattr-test

  docker exec ${syscont} sh -c "[ -x ${test_bin} ]"
  [ "$status" -eq 0 ]

  docker exec -d ${syscont} sh -c "unshare -m bash -c \"sleep 1000\""
  [ "$status" -eq 0 ]

  docker exec ${syscont} sh -c "pidof sleep"
  [ "$status" -eq 0 ]
  local inner_pid=$output

  local kernel_rel=$(__docker exec ${syscont} sh -c "uname -r")
  local immutable_ro_mounts=$(list_container_ro_mounts ${syscont} ${inner_pid} "/")

  local targets=()
  if grep -qxF "/usr/lib/modules/${kernel_rel}" <<< "${immutable_ro_mounts}"; then
    targets+=("/usr/lib/modules/${kernel_rel}")
  fi
  for m in ${immutable_ro_mounts}; do
    if [[ ${m} == "/usr/src/"* ]]; then
      targets+=("${m}")
    fi
  done

  if [ ${#targets[@]} -eq 0 ]; then
    docker_stop ${syscont}
    skip "no kernel header/module mounts present in this container"
  fi

  local target=/root/target

  for m in "${targets[@]}"; do
    printf "\ntesting mount_setattr(2) clear of read-only on a bind-mount of ${m}\n"

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} mkdir -p ${target}"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} mount --bind ${m} ${target}"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} touch ${target}"
    [ "$status" -ne 0 ]

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} ${test_bin} ${target}"
    [ "$status" -ne 0 ]

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} touch ${target}/canary"
    [ "$status" -ne 0 ]

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} umount ${target}"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} rm -rf ${target}"
    [ "$status" -eq 0 ]
  done

  docker_stop ${syscont}
}

# Testcase #16.
#
# Clean up the mount-setattr-test helper binary.
@test "mount-setattr-test cleanup -- unshare(mnt)" {
  pushd tests/syscall/mount/mount-setattr-test
  make clean
  popd
}
