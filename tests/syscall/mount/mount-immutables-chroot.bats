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

# Test to verify immutable mounts within a sys container's chroot() context.
#
# Note: a sys container immutable mount is a mount that is setup at container
# creation time.
#

chrootpath="/tmp/chrootdir"
immutable_ro_dir="ro_dir"
immutable_ro_file="ro_file"
immutable_masked_dir="masked_dir"
immutable_masked_file="masked_file"

immutable_ro_dir_path="${chrootpath}/${immutable_ro_dir}"
immutable_ro_file_path="${chrootpath}/${immutable_ro_file}"
immutable_masked_dir_path="${chrootpath}/${immutable_masked_dir}"
immutable_masked_file_path="${chrootpath}/${immutable_masked_file}"

function local_rootfs_prepare() {
  mkdir -p ${immutable_ro_dir_path}
  touch ${immutable_ro_file_path}
  mkdir -p ${immutable_masked_dir_path}
  touch ${immutable_masked_file_path}
}

# Testcase #1.
#
# Ensure immutable mounts can't be unmounted from inside the container if, and
# only if, sysbox-fs is running with 'allow-immutable-unmounts' option disabled.
# Alternatively, verify that unmounts are always allowed.
@test "immutable mount can't be unmounted -- chroot()" {

  local_rootfs_prepare

  local syscont=$(docker_run --rm -v ${immutable_ro_dir_path}:${immutable_ro_dir_path}:ro -v ${immutable_ro_file_path}:${immutable_ro_file_path}:ro --mount type=tmpfs,destination=${immutable_masked_dir_path} -v /dev/null:${immutable_masked_file_path} ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)

  chroot_prepare ${syscont} ${chrootpath}

  local immutable_mounts=$(list_container_mounts ${syscont} "0" ${chrootpath})
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

    docker exec ${syscont} sh -c "chroot ${chrootpath} umount ${m}"
    if [[ ${unmounts_allowed} -eq 0 ]]; then
      [ "$status" -eq 0 ]
    else
      [ "$status" -ne 0 ]
    fi
  done

  local immutable_mounts_after=$(list_container_mounts ${syscont} "0" ${chrootpath})
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
@test "immutable ro mount can't be remounted rw -- chroot()" {

  local syscont=$(docker_run --rm -v ${immutable_ro_dir_path}:${immutable_ro_dir_path}:ro -v ${immutable_ro_file_path}:${immutable_ro_file_path}:ro --mount type=tmpfs,destination=${immutable_masked_dir_path} -v /dev/null:${immutable_masked_file_path} ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)

  chroot_prepare ${syscont} ${chrootpath}

  local immutable_ro_mounts=$(list_container_ro_mounts ${syscont} "0" ${chrootpath})
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

    docker exec ${syscont} sh -c "chroot ${chrootpath} mount -o remount,bind,rw $m"
    if [[ ${remounts_allowed} -eq 0 ]]; then
      [ "$status" -eq 0 ]
    else
      [ "$status" -ne 0 ]
    fi
  done

  local immutable_ro_mounts_after=$(list_container_ro_mounts ${syscont} "0" ${chrootpath})
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
@test "immutable rw mount can be remounted ro -- chroot()" {

  local_rootfs_prepare

  local syscont=$(docker_run --rm -v ${immutable_ro_dir_path}:${immutable_ro_dir_path}:ro -v ${immutable_ro_file_path}:${immutable_ro_file_path}:ro --mount type=tmpfs,destination=${immutable_masked_dir_path} -v /dev/null:${immutable_masked_file_path} ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)

  chroot_prepare ${syscont} ${chrootpath}

  local immutable_rw_mounts=$(list_container_rw_mounts ${syscont} "0" ${chrootpath})
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

    docker exec ${syscont} sh -c "chroot ${chrootpath} mount -o remount,bind,ro ${m}"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "chroot ${chrootpath} mount -o remount,bind,rw ${m}"
    [ "$status" -eq 0 ]
  done

  docker_stop ${syscont}
}

# Testcase #4.
#
# Ensure that a read-only immutable mount *can* be remounted as read-only inside
# the container.
@test "immutable ro mount can be remounted ro -- chroot()" {

  local_rootfs_prepare

  local syscont=$(docker_run --rm -v ${immutable_ro_dir_path}:${immutable_ro_dir_path}:ro -v ${immutable_ro_file_path}:${immutable_ro_file_path}:ro --mount type=tmpfs,destination=${immutable_masked_dir_path} -v /dev/null:${immutable_masked_file_path} ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)

  chroot_prepare ${syscont} ${chrootpath}

  local immutable_ro_mounts=$(list_container_ro_mounts ${syscont} "0" ${chrootpath})
  run is_list_empty ${immutable_ro_mounts}
  [ "$status" -ne 0 ]

  for m in ${immutable_ro_mounts}; do
    printf "\ntesting ro remount of immutable ro mount ${m}\n"

    docker exec ${syscont} sh -c "chroot ${chrootpath} mount -o remount,bind,ro ${m}"
    [ "$status" -eq 0 ]
  done

  local immutable_ro_mounts_after=$(list_container_ro_mounts ${syscont} "0" ${chrootpath})
  [[ ${immutable_ro_mounts} == ${immutable_ro_mounts_after} ]]

  docker_stop ${syscont}
}

# Testcase #5.
#
# Ensure that a read-write immutable mount *can* be remounted as read-write
# inside the container.
@test "immutable rw mount can be remounted rw -- chroot()" {

  local_rootfs_prepare

  local syscont=$(docker_run --rm -v ${immutable_ro_dir_path}:${immutable_ro_dir_path}:ro -v ${immutable_ro_file_path}:${immutable_ro_file_path}:ro --mount type=tmpfs,destination=${immutable_masked_dir_path} -v /dev/null:${immutable_masked_file_path} ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)

  chroot_prepare ${syscont} ${chrootpath}

  local immutable_rw_mounts=$(list_container_rw_mounts ${syscont} "0" ${chrootpath})
  run is_list_empty ${immutable_rw_mounts}
  [ "$status" -ne 0 ]

  for m in ${immutable_rw_mounts}; do
    printf "\ntesting rw remount of immutable rw mount ${m}\n"

    docker exec ${syscont} sh -c "chroot ${chrootpath} mount -o remount,bind,rw ${m}"
    [ "$status" -eq 0 ]
  done

  local immutable_rw_mounts_after=$(list_container_rw_mounts ${syscont} "0" ${chrootpath})
  [[ ${immutable_rw_mounts} == ${immutable_rw_mounts_after} ]]

  docker_stop ${syscont}
}

# Testcase #6.
#
# Ensure that a read-only immutable mount can be bind-mounted to a new
# mountpoint, but not re-mounted read-write at the new mountpoint if, and only
# if, sysbox-fs is running with 'allow-immutable-remounts' knob disabled.
# Otherwise, allow remounts to succeed.
@test "immutable ro mount can't be bind-mounted rw -- chroot()" {

  local_rootfs_prepare

  local syscont=$(docker_run --rm -v ${immutable_ro_dir_path}:${immutable_ro_dir_path}:ro -v ${immutable_ro_file_path}:${immutable_ro_file_path}:ro --mount type=tmpfs,destination=${immutable_masked_dir_path} -v /dev/null:${immutable_masked_file_path} ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)

  chroot_prepare ${syscont} ${chrootpath}

  local immutable_ro_mounts=$(list_container_ro_mounts ${syscont} "0" ${chrootpath})
  run is_list_empty ${immutable_ro_mounts}
  [ "$status" -ne 0 ]
  local target="target"

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
    docker exec ${syscont} sh -c "chroot ${chrootpath} bash -c \"[[ -d ${m} ]]\""

    if [ "$status" -eq 0 ]; then
      docker exec ${syscont} sh -c "chroot ${chrootpath} mkdir -p ${target}"
      [ "$status" -eq 0 ]
    else
      docker exec ${syscont} sh -c "chroot ${chrootpath} touch ${target}"
      [ "$status" -eq 0 ]
    fi

    docker exec ${syscont} sh -c "chroot ${chrootpath} mount --bind ${m} ${target}"
    [ "$status" -eq 0 ]

    # Verify the bind-mount continues to be read-only
    docker exec ${syscont} sh -c "chroot ${chrootpath} touch ${target}"
    [ "$status" -ne 0 ]

    # This rw remount should fail if 'allow-immutable-remounts' knob is disabled
    # (default behavior).
    printf "\ntesting rw remount of immutable ro bind-mount ${target}\n"
    docker exec ${syscont} sh -c "mount -o remount,bind,rw ${target}"
    if [[ ${remounts_allowed} -eq 0 ]]; then
      [ "$status" -eq 0 ]
    else
      [ "$status" -ne 0 ]
    fi

    # This ro remount should pass (it's not needed but just to double-check)
    docker exec ${syscont} sh -c "chroot ${chrootpath} mount -o remount,bind,ro ${target}"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "chroot ${chrootpath} umount ${target}"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "chroot ${chrootpath} rm -rf ${target}"
    [ "$status" -eq 0 ]
  done

  docker_stop ${syscont}
}

# Testcase #7.
#
# Ensure that a read-write immutable mount can be bind-mounted to a new
# mountpoint then re-mounted read-only.
@test "immutable rw mount can be bind-mounted ro -- chroot()" {

  local_rootfs_prepare

  local syscont=$(docker_run --rm -v ${immutable_ro_dir_path}:${immutable_ro_dir_path}:ro -v ${immutable_ro_file_path}:${immutable_ro_file_path}:ro --mount type=tmpfs,destination=${immutable_masked_dir_path} -v /dev/null:${immutable_masked_file_path} ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)

  chroot_prepare ${syscont} ${chrootpath}

  local immutable_rw_mounts=$(list_container_rw_mounts ${syscont} "0" ${chrootpath})
  run is_list_empty ${immutable_rw_mounts}
  [ "$status" -ne 0 ]
  local target="target"

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
    docker exec ${syscont} bash -c "chroot ${chrootpath} bash -c \"[[ -d ${m} ]]\""

    if [ "$status" -eq 0 ]; then
      docker exec ${syscont} sh -c "chroot ${chrootpath} mkdir -p ${target}"
      [ "$status" -eq 0 ]
    else
      docker exec ${syscont} sh -c "chroot ${chrootpath} touch ${target}"
      [ "$status" -eq 0 ]
    fi

    docker exec ${syscont} sh -c "chroot ${chrootpath} mount --bind ${m} ${target}"
    [ "$status" -eq 0 ]

    # Verify the bind-mount continues to be read-write
    docker exec ${syscont} sh -c "chroot ${chrootpath} touch ${target}"
    [ "$status" -eq 0 ]

    # This ro remount should pass
    printf "\ntesting ro remount of immutable rw bind-mount ${target}\n"
    docker exec ${syscont} sh -c "chroot ${chrootpath} mount -o remount,bind,ro ${target}"
    [ "$status" -eq 0 ]

    # Verify the bind-mount is now read-only
    docker exec ${syscont} sh -c "chroot ${chrootpath} touch ${target}"
    [ "$status" -ne 0 ]

    # Verify the bind-mount source continues to be read-write
    docker exec ${syscont} sh -c "touch ${m}"
    [ "$status" -eq 0 ]

    # This rw remount should also pass
    docker exec ${syscont} sh -c "chroot ${chrootpath} mount -o remount,bind,rw ${target}"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "chroot ${chrootpath} umount ${target}"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "chroot ${chrootpath} rm -rf ${target}"
    [ "$status" -eq 0 ]
  done

  docker_stop ${syscont}
}

# Testcase #8.
#
# Ensure that a read-only immutable mount *can* be masked by a new read-write
# mount on top of it.
@test "rw mount on top of immutable ro mount -- chroot()" {

  local_rootfs_prepare

  local syscont=$(docker_run --rm -v ${immutable_ro_dir_path}:${immutable_ro_dir_path}:ro -v ${immutable_ro_file_path}:${immutable_ro_file_path}:ro --mount type=tmpfs,destination=${immutable_masked_dir_path} -v /dev/null:${immutable_masked_file_path} ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)

  chroot_prepare ${syscont} ${chrootpath}

  local immutable_ro_mounts=$(list_container_ro_mounts ${syscont} "0" ${chrootpath})
  run is_list_empty ${immutable_ro_mounts}
  [ "$status" -ne 0 ]

  for m in ${immutable_ro_dir_mounts}; do

    # skip /proc and /sys since these are special mounts (we have dedicated
    # tests for remounting them). We also
    if [[ ${m} =~ "/proc" ]] || [[ ${m} =~ "/proc/*" ]] ||
         [[ ${m} =~ "/sys" ]] || [[ ${m} =~ "/sys/*" ]] ||
         [[ ${m} =~ "/dev" ]] || [[ ${m} =~ "/dev/*" ]]; then
      continue
    fi

    # Skip directory mountpoints.
    docker exec ${syscont} bash -c "chroot ${chrootpath} bash -c \"[[ ! -d ${m} ]]\""
    if [ "$status" -eq 0 ]; then
      continue
    fi

    # This should fail (mount is read-only)
    docker exec ${syscont} sh -c "chroot ${chrootpath} touch ${m}"
    [ "$status" -ne 0 ]

    printf "\nmounting tmpfs (rw) on top of immutable ro mount ${m}\n"
    docker exec ${syscont} sh -c \
      "chroot ${chrootpath} mount -t tmpfs -o size=100M tmpfs ${m}"
    [ "$status" -eq 0 ]

    # This should pass (tmpfs mount is read-write)
    docker exec ${syscont} sh -c "chroot ${chrootpath} touch ${m}"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "chroot ${chrootpath} umount ${m}"
    [ "$status" -eq 0 ]

    # This should fail (mount is read-only)
    docker exec ${syscont} sh -c "chroot ${chrootpath} touch ${m}"
    [ "$status" -ne 0 ]
  done

  docker_stop ${syscont}
}

# Testcase #9.
#
# Ensure that a read-write immutable mount *can* be masked by a new read-only
# mount on top of it.
@test "ro mount on top of immutable rw mount -- chroot()" {

  local_rootfs_prepare

  local syscont=$(docker_run --rm -v ${immutable_ro_dir_path}:${immutable_ro_dir_path}:ro -v ${immutable_ro_file_path}:${immutable_ro_file_path}:ro --mount type=tmpfs,destination=${immutable_masked_dir_path} -v /dev/null:${immutable_masked_file_path} ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)

  chroot_prepare ${syscont} ${chrootpath}

  local immutable_rw_mounts=$(list_container_rw_mounts ${syscont} "0" ${chrootpath})
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
    docker exec ${syscont} bash -c "chroot ${chrootpath} bash -c \"[[ ! -d ${m} ]]\""
    if [ "$status" -eq 0 ]; then
      continue
    fi

    # This should pass (mount is read-write)
    docker exec ${syscont} sh -c "chroot ${chrootpath} touch ${m}"
    [ "$status" -eq 0 ]

    printf "\nmounting tmpfs (ro) on top of immutable rw mount ${m}\n"

    docker exec ${syscont} sh -c "chroot ${chrootpath} mount -t tmpfs -o ro,size=100M tmpfs ${m}"
    [ "$status" -eq 0 ]

    # This should fail (tmpfs mount is read-only)
    docker exec ${syscont} sh -c "chroot ${chrootpath} touch ${m}"
    [ "$status" -ne 0 ]

    docker exec ${syscont} sh -c "chroot ${chrootpath} umount ${m}"
    [ "$status" -eq 0 ]

    # This should pass (mount is read-write)
    docker exec ${syscont} sh -c "chroot ${chrootpath} touch ${m}"
    [ "$status" -eq 0 ]
  done

  docker_stop ${syscont}
}

# Testcase #10.
#
# Ensure proper execution of unmount ops over mount-stacks and bind-mount chains
# formed by regular files mountpoints.
@test "unmount chain of file bind-mounts -- chroot()" {

  local_rootfs_prepare

  local syscont=$(docker_run --rm -v ${immutable_ro_dir_path}:${immutable_ro_dir_path}:ro -v ${immutable_ro_file_path}:${immutable_ro_file_path}:ro --mount type=tmpfs,destination=${immutable_masked_dir_path} -v /dev/null:${immutable_masked_file_path} ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)

  chroot_prepare ${syscont} ${chrootpath}

  local immutable_mounts=$(list_container_mounts ${syscont} "0" ${chrootpath})
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

    # Skip directory mountpoints.
    docker exec ${syscont} bash -c "chroot ${chrootpath} bash -c \"[[ -d ${m} ]]\""
    if [ "$status" -eq 0 ]; then
      continue
    fi

    # Create bind-mount chain and verify the proper behavior of the unmount
    # operations attending to sysbox-fs runtime settings.
    docker exec ${syscont} sh -c "chroot ${chrootpath} touch ${m}2"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "chroot ${chrootpath} mount -o bind $m ${m}2"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "chroot ${chrootpath} umount ${m}2"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "chroot ${chrootpath} umount ${m}"
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
# formed by directory mountpoints.
@test "unmount chain of dir bind-mounts -- chroot()" {

  local_rootfs_prepare

  local syscont=$(docker_run --rm -v ${immutable_ro_dir_path}:${immutable_ro_dir_path}:ro -v ${immutable_ro_file_path}:${immutable_ro_file_path}:ro --mount type=tmpfs,destination=${immutable_masked_dir_path} -v /dev/null:${immutable_masked_file_path} ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)

  chroot_prepare ${syscont} ${chrootpath}

  local immutable_mounts=$(list_container_mounts ${syscont} "0" ${chrootpath})
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

    # Skip file mountpoints.
    docker exec ${syscont} bash -c "chroot ${chrootpath} bash -c \"[[ ! -d ${m} ]]\""
    if [ "$status" -eq 0 ]; then
      continue
    fi

    # Create mount-stack and verify that last two elements can be always
    # unmounted.
    docker exec ${syscont} sh -c "chroot ${chrootpath} mount -t tmpfs -o ro,size=100M tmpfs ${m}"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "chroot ${chrootpath} mount -t tmpfs -o ro,size=100M tmpfs ${m}"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "chroot ${chrootpath} umount ${m}"
    [ "$status" -eq 0 ]

    docker exec $syscont sh -c "chroot ${chrootpath} umount ${m}"
    [ "$status" -eq 0 ]

    # Create bind-mount chain and verify the proper behavior of the unmount
    # operations attending to sysbox-fs runtime settings.
    docker exec ${syscont} sh -c "chroot ${chrootpath} mkdir -p ${m}2 ${m}3"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "chroot ${chrootpath} mount -o bind ${m} ${m}2"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "chroot ${chrootpath} mount -o bind ${m}2 ${m}3"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "chroot ${chrootpath} umount ${m}3"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "chroot ${chrootpath} umount ${m}2"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c "chroot ${chrootpath} umount ${m}"
    if [[ ${unmounts_allowed} -eq 0 ]]; then
      [ "$status" -eq 0 ]
    else
      [ "$status" -ne 0 ]
    fi
  done

  docker_stop ${syscont}
}
