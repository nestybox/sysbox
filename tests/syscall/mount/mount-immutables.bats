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

# Test to verify immutable mounts within a sys container.
#
# Note: a sys container immutable mount is a mount that is setup at container
# creation time.
#

# Testcase #1.
#
# Ensure immutable mounts can't be unmounted from inside the container if, and
# only if, sysbox-fs is running with 'allow-immutable-unmounts' option disabled.
# Alternatively, verify that unmounts are always allowed.
@test "immutable mount can't be unmounted" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)
  local immutable_mounts=$(list_container_mounts ${syscont} "0" "/")
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

    printf "\ntesting unmount of immutable mount ${m}\n"

    docker exec ${syscont} sh -c "umount ${m}"
    if [[ ${unmounts_allowed} -eq 0 ]]; then
      [ "$status" -eq 0 ]
    else
      [ "$status" -ne 0 ]
    fi
  done

  local immutable_mounts_after=$(list_container_mounts ${syscont} "0" "/")
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
# from inside the container if, and only if, sysbox-fs is running with
# 'allow-immutable-remounts' option disabled. Alternatively, verify that
# remounts are allowed.
@test "immutable ro mount can't be remounted rw" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)
  local immutable_ro_mounts=$(list_container_ro_mounts ${syscont} "0" "/")
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
    # Skip /proc and /sys since these are special mounts (we have dedicated
    # tests that cover remounting ops).
    if [[ ${m} =~ "/proc" ]] || [[ ${m} =~ "/proc/*" ]] ||
        [[ ${m} =~ "/sys" ]] || [[ ${m} =~ "/sys/*" ]]; then
        continue
    fi

    printf "\ntesting rw remount of immutable ro mount ${m}\n"

    docker exec ${syscont} sh -c "mount -o remount,bind,rw ${m}"
    if [[ ${remounts_allowed} -eq 0 ]]; then
      [ "$status" -eq 0 ]
      # Verify mountpoint is now read-write.
      docker exec ${syscont} sh -c "touch ${m}"
      [ "$status" -eq 0 ]
    else
      [ "$status" -ne 0 ]
      # Verify mountpoint continues to be read-only.
      docker exec ${syscont} sh -c "touch ${m}"
      [ "$status" -ne 0 ]
    fi
  done

  local immutable_ro_mounts_after=$(list_container_ro_mounts ${syscont} "0" "/")
  if [[ ${remounts_allowed} -eq 0 ]]; then
    [[ $immutable_ro_mounts != $immutable_ro_mounts_after ]]
  else
    [[ $immutable_ro_mounts == $immutable_ro_mounts_after ]]
  fi

  docker_stop ${syscont}
}

# Testcase #3.
#
# Ensure that a read-write immutable mount *can* be remounted as read-only inside
# the container, and then back to read-write.
@test "immutable rw mount can be remounted ro" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)
  local immutable_rw_mounts=$(list_container_rw_mounts ${syscont} "0" "/")
  run is_list_empty ${immutable_rw_mounts}
  [ "$status" -ne 0 ]

  for m in $immutable_rw_mounts; do

    # Remounting /proc or /dev as read-only will prevent docker execs into the
    # container; skip these.
    if [[ ${m} =~ "/proc" ]] || [[ ${m} =~ "/proc/*" ]] ||
       [[ ${m} =~ "/dev" ]] || [[ ${m} =~ "/dev/*" ]]; then
      continue
    fi

    printf "\ntesting ro remount of immutable rw mount ${m}\n"

    docker exec ${syscont} sh -c "mount -o remount,bind,ro ${m}"
    [ "$status" -eq 0 ]

    # Verify mountpoint is now read-only.
    docker exec ${syscont} sh -c "touch ${m}"
    [ "$status" -ne 0 ]

    docker exec ${syscont} sh -c "mount -o remount,bind,rw ${m}"
    [ "$status" -eq 0 ]
  done

  docker_stop ${syscont}
}

# Testcase #4.
#
# Ensure that a read-only immutable mount *can* be remounted as read-only inside
# the container.
@test "immutable ro mount can be remounted ro" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)
  local immutable_ro_mounts=$(list_container_ro_mounts ${syscont} "0" "/")
  run is_list_empty ${immutable_ro_mounts}
  [ "$status" -ne 0 ]

  for m in $immutable_ro_mounts; do
    printf "\ntesting ro remount of immutable ro mount ${m}\n"

    docker exec ${syscont} sh -c "mount -o remount,bind,ro ${m}"
    [ "$status" -eq 0 ]

    # Verify mountpoint continues to be read-only.
    docker exec ${syscont} sh -c "touch ${m}"
    [ "$status" -ne 0 ]
  done

  local immutable_ro_mounts_after=$(list_container_ro_mounts ${syscont} "0" "/")
  [[ $immutable_ro_mounts == $immutable_ro_mounts_after ]]

  docker_stop ${syscont}
}

# Testcase #5.
#
# Ensure that a read-write immutable mount *can* be remounted as read-write
# inside the container.
@test "immutable rw mount can be remounted rw" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)
  local immutable_rw_mounts=$(list_container_rw_mounts ${syscont} "0" "/")
  run is_list_empty ${immutable_rw_mounts}
  [ "$status" -ne 0 ]

  for m in $immutable_rw_mounts; do
    # Skip /proc and /sys since these are special mounts (we have dedicated
    # tests that cover unmounting ops).
    if [[ ${m} =~ "/proc" ]] || [[ ${m} =~ "/proc/*" ]] ||
       [[ ${m} =~ "/sys" ]] || [[ ${m} =~ "/sys/*" ]]; then
       continue
    fi

    printf "\ntesting rw remount of immutable rw mount ${m}\n"

    docker exec ${syscont} sh -c "mount -o remount,bind,rw ${m}"
    [ "$status" -eq 0 ]

    # Verify mountpoint is now read-write.
    docker exec ${syscont} sh -c "touch ${m}"
    [ "$status" -eq 0 ]
  done

  local immutable_rw_mounts_after=$(list_container_rw_mounts ${syscont} "0" "/")
  [[ $immutable_rw_mounts == $immutable_rw_mounts_after ]]

  docker_stop ${syscont}
}

# Testcase #6.
#
# Ensure that a read-only immutable mount can be bind-mounted to a new
# mountpoint, but not re-mounted read-write at the new mountpoint if, and only
# if, sysbox-fs is running with 'allow-immutable-remounts' knob disabled.
# Otherwise, allow this remount to succeed.
@test "immutable ro mount can't be bind-mounted rw" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)
  local immutable_ro_mounts=$(list_container_ro_mounts ${syscont} "0" "/")
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
    # Skip /proc and /sys since these are special mounts (we have dedicated
    # tests that cover bind-mounting ops).
    if [[ ${m} =~ "/proc" ]] || [[ ${m} =~ "/proc/*" ]] ||
       [[ ${m} =~ "/sys" ]] || [[ ${m} =~ "/sys/*" ]]; then
       continue
    fi

    printf "\ntesting bind-mount of immutable ro mount ${m}\n"

    # Create bind-mount target (dir or file, depending on bind-mount source type)
    docker exec ${syscont} bash -c "[[ -d ${m} ]]"
    if [ "$status" -eq 0 ]; then
      docker exec ${syscont} sh -c "mkdir -p $target"
      [ "$status" -eq 0 ]
    else
      docker exec ${syscont} sh -c "touch $target"
      [ "$status" -eq 0 ]
    fi

    docker exec ${syscont} sh -c "mount --bind ${m} $target"
    [ "$status" -eq 0 ]

    # Verify the bind-mount continues to be read-only.
    docker exec ${syscont} sh -c "touch $target"
    [ "$status" -ne 0 ]

    # This rw remount should fail if 'allow-immutable-remounts' knob is disabled
    # (default behavior).
    printf "\ntesting rw remount of immutable ro bind-mount $target\n"
    docker exec ${syscont} sh -c "mount -o remount,bind,rw $target"
    if [[ ${remounts_allowed} -eq 0 ]]; then
      [ "$status" -eq 0 ]
      # Verify the bind-mount is now read-write.
      docker exec ${syscont} sh -c "touch $target"
      [ "$status" -eq 0 ]
    else
      [ "$status" -ne 0 ]
      # Verify the bind-mount continues to be read-only.
      docker exec ${syscont} sh -c "touch $target"
      [ "$status" -ne 0 ]
    fi

    # This ro remount should pass (it's not needed but just to double-check)
    docker exec ${syscont} sh -c "mount -o remount,bind,ro $target"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "umount $target"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "rm -rf $target"
    [ "$status" -eq 0 ]
  done

  docker_stop ${syscont}
}

# Testcase #7.
#
# Ensure that a read-write immutable mount can be bind-mounted to a new
# mountpoint and then re-mounted read-only.
@test "immutable rw mount can be bind-mounted ro" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)
  local immutable_rw_mounts=$(list_container_rw_mounts ${syscont} "0" "/")
  run is_list_empty ${immutable_rw_mounts}
  [ "$status" -ne 0 ]
  local target=/root/target

  for m in $immutable_rw_mounts; do

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
      docker exec ${syscont} sh -c "mkdir -p $target"
      [ "$status" -eq 0 ]
    else
      docker exec ${syscont} sh -c "touch $target"
      [ "$status" -eq 0 ]
    fi

    docker exec ${syscont} sh -c "mount --bind ${m} $target"
    [ "$status" -eq 0 ]

    # Verify the bind-mount continues to be read-write.
    docker exec ${syscont} sh -c "touch $target"
    [ "$status" -eq 0 ]

    # This ro remount should pass
    printf "\ntesting ro remount of immutable rw bind-mount $target\n"
    docker exec ${syscont} sh -c "mount -o remount,bind,ro $target"
    [ "$status" -eq 0 ]

    # Verify the bind-mount is now read-only.
    docker exec ${syscont} sh -c "touch $target"
    [ "$status" -ne 0 ]

    # Verify the bind-mount source continues to be read-write.
    docker exec ${syscont} sh -c "touch ${m}"
    [ "$status" -eq 0 ]

    # This rw remount should also pass.
    docker exec ${syscont} sh -c "mount -o remount,bind,rw $target"
    [ "$status" -eq 0 ]

    # Verify the bind-mount is read-write.
    docker exec ${syscont} sh -c "touch $target"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "umount $target"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "rm -rf $target"
    [ "$status" -eq 0 ]
  done

  docker_stop ${syscont}
}

# Testcase #8.
#
# Ensure that a read-only immutable mount *can* be masked by a new read-write
# mount on top of it.
@test "rw mount on top of immutable ro mount" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)
  local immutable_ro_mounts=$(list_container_ro_mounts ${syscont} "0" "/")
  run is_list_empty ${immutable_ro_mounts}
  [ "$status" -ne 0 ]

  for m in $immutable_ro_mounts; do

    # skip /proc and /sys since these are special mounts (we have dedicated
    # tests for remounting them). We also
    if [[ ${m} =~ "/proc" ]] || [[ ${m} =~ "/proc/*" ]] ||
         [[ ${m} =~ "/sys" ]] || [[ ${m} =~ "/sys/*" ]] ||
         [[ ${m} =~ "/dev" ]] || [[ ${m} =~ "/dev/*" ]]; then
      continue
    fi

    # This should fail (mount is read-only)
    docker exec ${syscont} sh -c "touch ${m}"
    [ "$status" -ne 0 ]

    printf "\nmounting tmpfs (rw) on top of immutable ro mount ${m}\n"

    docker exec ${syscont} sh -c "mount -t tmpfs -o size=100M tmpfs ${m}"
    [ "$status" -eq 0 ]

    # This should pass (tmpfs mount is read-write)
    docker exec ${syscont} sh -c "touch ${m}"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "umount ${m}"
    [ "$status" -eq 0 ]

    # This should fail (mount is read-only)
    docker exec ${syscont} sh -c "touch ${m}"
    [ "$status" -ne 0 ]
  done

  docker_stop ${syscont}
}

# Testcase #9.
#
# Ensure that a read-write immutable mount *can* be masked by a new read-only
# mount on top of it.
@test "ro mount on top of immutable rw mount" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)
  local immutable_rw_mounts=$(list_container_rw_dir_mounts ${syscont} "0" "/")
  run is_list_empty ${immutable_rw_mounts}
  [ "$status" -ne 0 ]
  echo ${immutable_rw_mounts} > /work_list

  for m in $immutable_rw_mounts; do

    # skip /proc and /sys since these are special mounts (we have dedicated
    # tests for remounting them). We also
    if [[ ${m} =~ "/proc" ]] || [[ ${m} =~ "/proc/*" ]] ||
         [[ ${m} =~ "/sys" ]] || [[ ${m} =~ "/sys/*" ]] ||
         [[ ${m} =~ "/dev" ]] || [[ ${m} =~ "/dev/*" ]]; then
      continue
    fi

    # This should pass (mount is read-write)
    docker exec ${syscont} sh -c "touch ${m}"
    [ "$status" -eq 0 ]

    printf "\nmounting tmpfs (ro) on top of immutable rw mount ${m}\n"

    docker exec ${syscont} sh -c "mount -t tmpfs -o ro,size=100M tmpfs ${m}"
    [ "$status" -eq 0 ]

    # This should fail (tmpfs mount is read-only)
    docker exec ${syscont} sh -c "touch ${m}"
    [ "$status" -ne 0 ]

    docker exec ${syscont} sh -c "umount ${m}"
    [ "$status" -eq 0 ]

    # This should pass (mount is read-write)
    docker exec ${syscont} sh -c "touch ${m}"
    [ "$status" -eq 0 ]
  done

  docker_stop ${syscont}
}

# Testcase #10.
@test "don't confuse inner priv container mount with immutable mount" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg tail -f /dev/null)
  local immutable_ro_mounts=$(list_container_ro_mounts ${syscont} "0" "/")
  run is_list_empty ${immutable_ro_mounts}
  [ "$status" -ne 0 ]

  local linux_libmod_mount=$(echo $immutable_ro_mounts |  tr ' ' '\n' | grep "lib/modules")

  [ -n "$linux_libmod_mount" ]

  docker exec -d ${syscont} sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd ${syscont}

  docker exec ${syscont} sh -c "docker run --privileged -d --name inner ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null"
  [ "$status" -eq 0 ]

  # In the inner container, create a dir and mountpoint whose name matches that
  # of an immutable sysbox mount
  docker exec ${syscont} sh -c "docker exec inner sh -c \"mkdir -p $linux_libmod_mount\""
  [ "$status" -eq 0 ]

  docker exec ${syscont} sh -c "docker exec inner sh -c \"mount --bind $linux_libmod_mount $linux_libmod_mount\""
  [ "$status" -eq 0 ]

  # Verify we can write, remount, and umount the newly created mountpoint without problem
  docker exec ${syscont} sh -c "docker exec inner sh -c \"touch $linux_libmod_mount\""
  [ "$status" -eq 0 ]

  docker exec ${syscont} sh -c "docker exec inner sh -c \"mount -o remount,bind,ro $linux_libmod_mount\""
  [ "$status" -eq 0 ]

  # Verify mountpoint is now read-only.
  docker exec ${syscont} sh -c "docker exec inner sh -c \"touch $linux_libmod_mount\""
  [ "$status" -ne 0 ]

  docker exec ${syscont} sh -c "docker exec inner sh -c \"mount -o remount,bind,rw $linux_libmod_mount\""
  [ "$status" -eq 0 ]

  # Verify mountpoint is now read-write.
  docker exec ${syscont} sh -c "docker exec inner sh -c \"touch $linux_libmod_mount\""
  [ "$status" -eq 0 ]

  docker exec ${syscont} sh -c "docker exec inner sh -c \"umount $linux_libmod_mount\""
  [ "$status" -eq 0 ]

  docker exec ${syscont} sh -c "docker stop -t0 inner"
  [ "$status" -eq 0 ]

  docker_stop ${syscont}
}

# Testcase #11.
#
# Ensure proper execution of unmount ops over mount-stacks and bind-mount chains
# formed by regular files mountpoints.
@test "unmount chain of file bind-mounts" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)
  local immutable_file_mounts=$(list_container_file_mounts ${syscont} "0" "/")
  run is_list_empty ${immutable_file_mounts}
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
    docker exec ${syscont} bash -c "[[ ! -f ${m} ]]"
    if [ "$status" -eq 0 ]; then
      continue
    fi

    # Create mount-stack and verify that the last element can be always
    # unmounted.
    docker exec ${syscont} sh -c "mount -o bind /dev/null ${m}"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "umount ${m}"
    [ "$status" -eq 0 ]

    # Create bind-mount chain and verify the proper behavior of the unmount
    # operations attending to sysbox-fs runtime settings.
    docker exec ${syscont} sh -c "touch ${m}2"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "mount -o bind ${m} ${m}2"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "umount ${m}2"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "umount ${m}"
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
# formed by character-file mountpoints.
@test "unmount chain of char bind-mounts" {

  local syscont=$(docker_run --rm -v /dev/null:/usr/bin/dpkg-maintscript-helper ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)
  local immutable_char_mounts=$(list_container_char_mounts ${syscont} "0" "/")
  run is_list_empty ${immutable_char_mounts}
  [ "$status" -ne 0 ]

  # Determine the mode in which to operate.
  local unmounts_allowed
  run allow_immutable_unmounts
  if [ "${status}" -eq 0 ]; then
    unmounts_allowed=0
  else
    unmounts_allowed=1
  fi

  for m in ${immutable_char_mounts}; do
    # Skip /proc and /sys since these are special mounts (we have dedicated
    # tests that cover unmounting ops).
    if [[ ${m} =~ "/proc" ]] || [[ ${m} =~ "/proc/*" ]] ||
        [[ ${m} =~ "/sys" ]] || [[ ${m} =~ "/sys/*" ]] ||
        [[ ${m} =~ "/dev" ]] || [[ ${m} =~ "/dev/*" ]]; then
      continue
    fi

    # Skip non-char mountpoints.
    docker exec ${syscont} bash -c "[[ ! -c ${m} ]]"
    if [ "$status" -eq 0 ]; then
      continue
    fi

    # Create mount-stack and verify that last element can be always
    # unmounted.
    docker exec ${syscont} sh -c "mount -o bind /dev/null ${m}"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "umount ${m}"
    [ "$status" -eq 0 ]

    # Create  bind-mount chain and verify the proper behavior of the unmount
    # operations attending to sysbox-fs runtime settings.
    docker exec ${syscont} sh -c "touch ${m}2"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "mount -o bind ${m} ${m}2"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "umount ${m}2"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "umount ${m}"
    if [[ ${unmounts_allowed} -eq 0 ]]; then
      [ "$status" -eq 0 ]
    else
      [ "$status" -ne 0 ]
    fi

  done

  docker_stop ${syscont}
}

# Testcase #13.
#
# Ensure proper execution of unmount ops over mount-stacks and bind-mount chains
# formed by directory mountpoints.
@test "unmount chain of dir bind-mounts" {

  local syscont=$(docker_run --rm --mount type=tmpfs,destination=/app ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)
  local immutable_dir_mounts=$(list_container_dir_mounts ${syscont} "0" "/")
  run is_list_empty ${immutable_dir_mounts}
  [ "$status" -ne 0 ]

  # Determine the mode in which to operate.
  local unmounts_allowed
  run allow_immutable_unmounts
  if [ "${status}" -eq 0 ]; then
    unmounts_allowed=0
  else
    unmounts_allowed=1
  fi

  for m in ${immutable_dir_mounts}; do
    # Skip /proc and /sys since these are special mounts (we have dedicated
    # tests that cover these unmounting ops).
    if [[ ${m} =~ "/proc" ]] || [[ ${m} =~ "/proc/*" ]] ||
        [[ ${m} =~ "/sys" ]] || [[ ${m} =~ "/sys/*" ]] ||
        [[ ${m} =~ "/dev" ]] || [[ ${m} =~ "/dev/*" ]]; then
      continue
    fi

    # Skip non-dir mountpoints.
    docker exec ${syscont} bash -c "[[ ! -d ${m} ]]"
    if [ "$status" -eq 0 ]; then
      continue
    fi

    # Create mount-stack and verify that last two elements can be always
    # unmounted.
    docker exec ${syscont} sh -c "mount -t tmpfs -o ro,size=100M tmpfs ${m}"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "mount -t tmpfs -o ro,size=100M tmpfs ${m}"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "umount ${m}"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "umount ${m}"
    [ "$status" -eq 0 ]

    # Create mount targets.
    docker exec ${syscont} sh -c "mkdir -p ${m}2 && mkdir -p ${m}3"
    [ "$status" -eq 0 ]

    # Create bind-mount chain and verify the proper behavior of the unmount
    # operations attending to sysbox-fs runtime settings.
    docker exec ${syscont} sh -c "mount -o bind ${m} ${m}2"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "mount -o bind ${m}2 ${m}3"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "umount ${m}3"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "umount ${m}2"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "umount ${m}"
    if [[ ${unmounts_allowed} -eq 0 ]]; then
      [ "$status" -eq 0 ]
    else
      [ "$status" -ne 0 ]
    fi
  done

  docker_stop ${syscont}
}

# Testcase #14.
#
# Ensure that root mountpoint ('/') cannot be altered by remount instruction
# if this one is initially mounted as 'read-only' (e.g docker's --read-only
# rootfs knob). As it's the case with regular mountpoints, user can bypass this
# restriction by setting sysbox-fs' 'allow-immutable-remounts=true' knob.
@test "remount rootfs on read-only sys container" {

  local syscont=$(docker_run --rm --read-only ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)

  # Determine the mode in which to operate.
  local remounts_allowed
  run allow_immutable_remounts
  if [ "${status}" -eq 0 ]; then
    remounts_allowed=0
  else
    remounts_allowed=1
  fi

  # Verify '/' mountpoint is indeed read-only.
  docker exec ${syscont} sh -c "touch /"
  [ "$status" -ne 0 ]

  printf "\ntesting RO remount of '/' on read-only sys container\n"

  # Always expected to pass.
  docker exec ${syscont} sh -c "mount -o remount,bind,ro /"
  [ "$status" -eq 0 ]

  printf "\ntesting RW remount of '/' on read-only sys container\n"

  docker exec ${syscont} sh -c "mount -o remount,bind,rw /"
  if [[ ${remounts_allowed} -eq 0 ]]; then
    [ "$status" -eq 0 ]
    # Verify mountpoint is now read-write.
    docker exec ${syscont} sh -c "touch /"
    [ "$status" -eq 0 ]
  else
    [ "$status" -ne 0 ]
    # Verify mountpoint continues to be read-only.
    docker exec ${syscont} sh -c "touch /"
    [ "$status" -ne 0 ]
  fi

  docker_stop ${syscont}
}

# Testcase #15.
#
# Ensure that targets with a softlink along their path can be properly unmounted (see docker/sysbox-fs
# PR #17). For this testcase to be relevant, the 'allow-immutable-umount=false' config knob must be set.
@test "allow umount of softlinked mountpoints" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)

  # Create a mountpoint whose target contains a softlink.
  docker exec ${syscont} sh -c "mkdir /var/test2 /var/test3 && ln -sf /var/test2 /var/test1 && mount -o bind /var/test1 /var/test3"
  [ "$status" -eq 0 ]

  # Verify that the target is properly mounted reflecting the softlink destination (/var/test2) as the
  # source of the bindmount.
  docker exec ${syscont} sh -c "cat /proc/self/mountinfo | egrep -q \"/var/test2 /var/test3\""
  [ "$status" -eq 0 ]

  # Verify that the unmount operation can be successfully executed when using the softlink destination as
  # the target of the unmount.
  docker exec ${syscont} sh -c "umount /var/test3"
  [ "$status" -eq 0 ]

  # Verify that the target was unmounted.
  docker exec ${syscont} sh -c "cat /proc/self/mountinfo | egrep -q \"/var/test2 /var/test3\""
  [ "$status" -ne 0 ]

  docker_stop ${syscont}
}
