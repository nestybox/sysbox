#!/usr/bin/env bats

#
# Verify trapping & emulation on "mount" and "unmount2" syscalls
#

load ../../helpers/run
load ../../helpers/syscall
load ../../helpers/docker
load ../../helpers/environment
load ../../helpers/mounts
load ../../helpers/sysbox-health

skipTest=0

function teardown() {
  sysbox_log_check
}

#
# Test to verify immutable mounts within a sys container's unshare(mnt) +
# chroot() context.
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
# Ensure immutable mounts can't be unmounted from inside an inner mount
# namespace.
@test "immutable mount can't be unmounted -- unshare(mnt) + chroot()" {
  if [[ $skipTest -eq 1 ]]; then
    skip
  fi
  local_rootfs_prepare

  local syscont=$(docker_run --rm -v ${immutable_ro_dir_path}:${immutable_ro_dir_path}:ro -v ${immutable_ro_file_path}:${immutable_ro_file_path}:ro --mount type=tmpfs,destination=${immutable_masked_dir_path} -v /dev/null:${immutable_masked_file_path} ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)
  
  docker exec -d ${syscont} sh -c "unshare -m bash -c \"sleep 1000\""
  [ "$status" -eq 0 ]

  docker exec ${syscont} sh -c "pidof sleep"
  [ "$status" -eq 0 ]
  local inner_pid=$output

  chroot_prepare_nsenter ${syscont} ${inner_pid} ${chrootpath}
  
  local immutable_mounts=$(list_container_mounts ${syscont} ${inner_pid} ${chrootpath})
  run empty_list ${immutable_mounts}
  [ "$status" -ne 0 ]

  for m in ${immutable_mounts}; do
    # Skip /proc and /sys since these are special mounts (we have dedicated
    # tests that cover unmounting ops).
    if [[ ${m} =~ "/proc" ]] || [[ ${m} =~ "/proc/*" ]] ||
        [[ ${m} =~ "/sys" ]] || [[ ${m} =~ "/sys/*" ]]; then
        continue
    fi

    printf "\ntesting unmount of immutable mount ${m}\n"

    docker exec ${syscont} sh -c "nsenter -a -t ${inner_pid} chroot ${chrootpath} umount ${m}"
    [ "$status" -ne 0 ]
  done

  local immutable_mounts_after=$(list_container_mounts ${syscont} ${inner_pid} ${chrootpath})
  [[ $immutable_mounts == $immutable_mounts_after ]]

  docker_stop ${syscont}
}

# Testcase #2.
#
# Ensure that a read-only immutable mount can't be remounted as read-write
# inside an inner mount namespace.
@test "immutable ro mount can't be remounted rw -- unshare(mnt) + chroot()" {
  if [[ $skipTest -eq 1 ]]; then
    skip
  fi
  local_rootfs_prepare

  local syscont=$(docker_run --rm -v ${immutable_ro_dir_path}:${immutable_ro_dir_path}:ro -v ${immutable_ro_file_path}:${immutable_ro_file_path}:ro --mount type=tmpfs,destination=${immutable_masked_dir_path} -v /dev/null:${immutable_masked_file_path} ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)
  
  docker exec -d ${syscont} sh -c "unshare -m bash -c \"sleep 1000\""
  [ "$status" -eq 0 ]

  docker exec ${syscont} sh -c "pidof sleep"
  [ "$status" -eq 0 ]
  local inner_pid=$output

  chroot_prepare_nsenter ${syscont} ${inner_pid} ${chrootpath}

  local immutable_ro_mounts=$(list_container_ro_mounts ${syscont} ${inner_pid} ${chrootpath})
  run empty_list ${immutable_ro_mounts}
  [ "$status" -ne 0 ]  

  for m in $immutable_ro_mounts; do
    printf "\ntesting rw remount of immutable ro mount ${m}\n"

    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} mount -o remount,bind,rw ${m}"
    [ "$status" -ne 0 ]
  done

  local immutable_ro_mounts_after=$(list_container_ro_mounts ${syscont} ${inner_pid} ${chrootpath})
  [[ $immutable_ro_mounts == $immutable_ro_mounts_after ]]

  docker_stop ${syscont}
}

# Testcase #3.
#
# Ensure that a read-write immutable mount *can* be remounted as read-only inside
# an inner mount namespace, and then back to read-only.
@test "immutable rw mount can be remounted ro -- unshare(mnt) + chroot()" {
  if [[ $skipTest -eq 1 ]]; then
    skip
  fi
  local_rootfs_prepare

  local syscont=$(docker_run --rm -v ${immutable_ro_dir_path}:${immutable_ro_dir_path}:ro -v ${immutable_ro_file_path}:${immutable_ro_file_path}:ro --mount type=tmpfs,destination=${immutable_masked_dir_path} -v /dev/null:${immutable_masked_file_path} ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)
  
  docker exec -d ${syscont} sh -c "unshare -m bash -c \"sleep 1000\""
  [ "$status" -eq 0 ]

  docker exec ${syscont} sh -c "pidof sleep"
  [ "$status" -eq 0 ]
  local inner_pid=$output

  chroot_prepare_nsenter ${syscont} ${inner_pid} ${chrootpath}

  local immutable_rw_mounts=$(list_container_rw_mounts ${syscont} ${inner_pid} ${chrootpath})
  run empty_list ${immutable_rw_mounts}
  [ "$status" -ne 0 ]  

  for m in ${immutable_rw_mounts}; do

    # Remounting /proc or /dev as read-only will prevent docker execs into the
    # container; skip these.
    if [[ ${m} =~ "/proc" ]] || [[ ${m} =~ "/proc/*" ]] ||
       [[ ${m} =~ "/dev" ]] || [[ ${m} =~ "/dev/*" ]]; then
      continue
    fi

    printf "\ntesting ro remount of immutable rw mount ${m}\n"

    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} mount -o remount,bind,ro ${m}"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} mount -o remount,bind,rw ${m}"
    [ "$status" -eq 0 ]
  done

  docker_stop ${syscont}
}

# Testcase #4.
#
# Ensure that a read-only immutable mount *can* be remounted as read-only inside
# an inner mount namespace.
@test "immutable ro mount can be remounted ro -- unshare(mnt) + chroot()" {
  if [[ $skipTest -eq 1 ]]; then
    skip
  fi
  local_rootfs_prepare

  local syscont=$(docker_run --rm -v ${immutable_ro_dir_path}:${immutable_ro_dir_path}:ro -v ${immutable_ro_file_path}:${immutable_ro_file_path}:ro --mount type=tmpfs,destination=${immutable_masked_dir_path} -v /dev/null:${immutable_masked_file_path} ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)
  
  docker exec -d ${syscont} sh -c "unshare -m bash -c \"sleep 1000\""
  [ "$status" -eq 0 ]

  docker exec ${syscont} sh -c "pidof sleep"
  [ "$status" -eq 0 ]
  local inner_pid=$output

  chroot_prepare_nsenter ${syscont} ${inner_pid} ${chrootpath}

  local immutable_ro_mounts=$(list_container_ro_mounts ${syscont} ${inner_pid} ${chrootpath})
  run empty_list ${immutable_ro_mounts}
  [ "$status" -ne 0 ]  

  for m in ${immutable_ro_mounts}; do
    printf "\ntesting ro remount of immutable ro mount ${m}\n"

    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} mount -o remount,bind,ro ${m}"
    [ "$status" -eq 0 ]
  done

  local immutable_ro_mounts_after=$(list_container_ro_mounts ${syscont} ${inner_pid} ${chrootpath})
  [[ $immutable_ro_mounts == $immutable_ro_mounts_after ]]

  docker_stop ${syscont}
}

# Testcase #5.
#
# Ensure that a read-write immutable mount *can* be remounted as read-write or
# read-only inside an inner mount namespace.
@test "immutable rw mount can be remounted rw -- unshare(mnt) + chroot()" {
  if [[ $skipTest -eq 1 ]]; then
    skip
  fi
  local_rootfs_prepare

  local syscont=$(docker_run --rm -v ${immutable_ro_dir_path}:${immutable_ro_dir_path}:ro -v ${immutable_ro_file_path}:${immutable_ro_file_path}:ro --mount type=tmpfs,destination=${immutable_masked_dir_path} -v /dev/null:${immutable_masked_file_path} ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)
  
  docker exec -d ${syscont} sh -c "unshare -m bash -c \"sleep 1000\""
  [ "$status" -eq 0 ]

  docker exec ${syscont} sh -c "pidof sleep"
  [ "$status" -eq 0 ]
  local inner_pid=$output

  chroot_prepare_nsenter ${syscont} ${inner_pid} ${chrootpath}

  local immutable_rw_mounts=$(list_container_rw_mounts ${syscont} ${inner_pid} ${chrootpath})
  run empty_list ${immutable_rw_mounts}
  [ "$status" -ne 0 ]

  for m in ${immutable_rw_mounts}; do
    printf "\ntesting rw remount of immutable rw mount ${m}\n"

    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} mount -o remount,bind,rw ${m}"    
    [ "$status" -eq 0 ]
  done

  local immutable_rw_mounts_after=$(list_container_rw_mounts ${syscont} ${inner_pid} ${chrootpath})
  [[ $immutable_rw_mounts == $immutable_rw_mounts_after ]]

  docker_stop ${syscont}
}

# Testcase #6.
#
# Within an inner mount namespace, ensure that a read-only immutable mount can't
# be bind-mounted to a new mountpoint then re-mounted read-write.
@test "immutable ro mount can't be bind-mounted rw -- unshare(mnt) + chroot()" {
  if [[ $skipTest -eq 1 ]]; then
    skip
  fi
  local_rootfs_prepare

  local syscont=$(docker_run --rm -v ${immutable_ro_dir_path}:${immutable_ro_dir_path}:ro -v ${immutable_ro_file_path}:${immutable_ro_file_path}:ro --mount type=tmpfs,destination=${immutable_masked_dir_path} -v /dev/null:${immutable_masked_file_path} ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)
  
  docker exec -d ${syscont} sh -c "unshare -m bash -c \"sleep 1000\""
  [ "$status" -eq 0 ]

  docker exec ${syscont} sh -c "pidof sleep"
  [ "$status" -eq 0 ]
  local inner_pid=$output

  chroot_prepare_nsenter ${syscont} ${inner_pid} ${chrootpath}

  local immutable_ro_mounts=$(list_container_ro_mounts ${syscont} ${inner_pid} ${chrootpath})
  run empty_list ${immutable_ro_mounts}
  [ "$status" -ne 0 ]  
  local target="target"

  for m in ${immutable_ro_mounts}; do

    printf "\ntesting bind-mount of immutable ro bind-mount ${m}-> ${target}\n"

    # Create bind-mount target (dir or file, depending on bind-mount source type)
    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} bash -c \"[[ -d ${m} ]]\""

    if [ "$status" -eq 0 ]; then
      docker exec ${syscont} sh -c \
        "nsenter -a -t ${inner_pid} chroot ${chrootpath} mkdir -p ${target}"
      [ "$status" -eq 0 ]
    else
      docker exec ${syscont} sh -c \
        "nsenter -a -t ${inner_pid} chroot ${chrootpath} touch ${target}"
      [ "$status" -eq 0 ]
    fi

    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} mount --bind ${m} ${target}"
    [ "$status" -eq 0 ]

    # Verify the bind-mount continues to be read-only
    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} touch ${target}"
    [ "$status" -ne 0 ]

    # This rw remount should fail
    printf "\ntesting rw remount of immutable ro bind-mount ${target}\n"
    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} mount -o remount,bind,rw $target"
    [ "$status" -ne 0 ]

    # This ro remount should pass (it's not needed but just to double-check)
    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} mount -o remount,bind,ro $target"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} umount ${target}"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} rm -rf ${target}"
    [ "$status" -eq 0 ]
  done

  docker_stop ${syscont}
}

# Testcase #7.
#
# Within an inner mount namespace, ensure that a read-write immutable mount can
# be bind-mounted to a new mountpoint then re-mounted read-only.
@test "immutable rw mount can be bind-mounted ro -- unshare(mnt) + chroot()" {
  if [[ $skipTest -eq 1 ]]; then
    skip
  fi
  local_rootfs_prepare

  local syscont=$(docker_run --rm -v ${immutable_ro_dir_path}:${immutable_ro_dir_path}:ro -v ${immutable_ro_file_path}:${immutable_ro_file_path}:ro --mount type=tmpfs,destination=${immutable_masked_dir_path} -v /dev/null:${immutable_masked_file_path} ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)
  
  docker exec -d ${syscont} sh -c "unshare -m bash -c \"sleep 1000\""
  [ "$status" -eq 0 ]

  docker exec ${syscont} sh -c "pidof sleep"
  [ "$status" -eq 0 ]
  local inner_pid=$output

  chroot_prepare_nsenter ${syscont} ${inner_pid} ${chrootpath}

  local immutable_rw_mounts=$(list_container_rw_mounts ${syscont} ${inner_pid} ${chrootpath})
  run empty_list ${immutable_rw_mounts}
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

    printf "\ntesting bind-mount of immutable rw bind-mount ${m}-> ${target}\n"

    # Create bind-mount target (dir or file, depending on bind-mount source type)
    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} bash -c \"[[ -d ${m} ]]\""

    if [ "$status" -eq 0 ]; then
      docker exec ${syscont} sh -c \
        "nsenter -a -t ${inner_pid} chroot ${chrootpath} mkdir -p ${target}"
      [ "$status" -eq 0 ]
    else
      docker exec ${syscont} sh -c \
        "nsenter -a -t ${inner_pid} chroot ${chrootpath} touch ${target}"
      [ "$status" -eq 0 ]
    fi

    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} mount --bind ${m} ${target}"
    [ "$status" -eq 0 ]

    # Verify the bind-mount continues to be read-write
    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} touch ${target}"
    [ "$status" -eq 0 ]

    # This ro remount should pass
    printf "\ntesting ro remount of immutable rw bind-mount ${target}\n"
    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} mount -o remount,bind,ro ${target}"
    [ "$status" -eq 0 ]

    # Verify the bind-mount is now read-only
    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} touch ${target}"
    [ "$status" -ne 0 ]

    # Verify the bind-mount source continues to be read-write
    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} touch ${m}"
    [ "$status" -eq 0 ]

    # This rw remount should also pass
    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} mount -o remount,bind,rw ${target}"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} umount ${target}"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} rm -rf ${target}"
    [ "$status" -eq 0 ]
  done

  docker_stop ${syscont}
}

# Testcase #8.
#
# Within an inner mount namespace, ensure that a read-only immutable mount
# *can* be masked by a new read-write mount on top of it.
@test "rw mount on top of immutable ro mount -- unshare(mnt) + chroot()" {
  if [[ $skipTest -eq 1 ]]; then
    skip
  fi
  local_rootfs_prepare

  local syscont=$(docker_run --rm -v ${immutable_ro_dir_path}:${immutable_ro_dir_path}:ro -v ${immutable_ro_file_path}:${immutable_ro_file_path}:ro --mount type=tmpfs,destination=${immutable_masked_dir_path} -v /dev/null:${immutable_masked_file_path} ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)
  
  docker exec -d ${syscont} sh -c "unshare -m bash -c \"sleep 1000\""
  [ "$status" -eq 0 ]

  docker exec ${syscont} sh -c "pidof sleep"
  [ "$status" -eq 0 ]
  local inner_pid=$output

  chroot_prepare_nsenter ${syscont} ${inner_pid} ${chrootpath}

  local immutable_ro_mounts=$(list_container_ro_mounts ${syscont} ${inner_pid} ${chrootpath})
  run empty_list ${immutable_ro_mounts}
  [ "$status" -ne 0 ]  

  for m in ${immutable_ro_mounts}; do

    # skip /proc and /sys since these are special mounts (we have dedicated
    # tests for remounting them). We also
    if [[ ${m} =~ "/proc" ]] || [[ ${m} =~ "/proc/*" ]] ||
         [[ ${m} =~ "/sys" ]] || [[ ${m} =~ "/sys/*" ]] ||
         [[ ${m} =~ "/dev" ]] || [[ ${m} =~ "/dev/*" ]]; then
      continue
    fi

    # Skip directory mountpoints.
    docker exec ${syscont} bash -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} bash -c \"[[ ! -d ${m} ]]\""
    if [ "$status" -eq 0 ]; then
      continue
    fi

    # This should fail (mount is read-only)
    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} touch ${m}"
    [ "$status" -ne 0 ]

    printf "\nmounting tmpfs (rw) on top of immutable ro mount ${m}\n"

    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} mount -t tmpfs -o size=100M tmpfs ${m}"
    [ "$status" -eq 0 ]

    # This should pass (tmpfs mount is read-write)
    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} touch ${m}"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} umount ${m}"
    [ "$status" -eq 0 ]

    # This should fail (mount is read-only)
    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} touch ${m}"
    [ "$status" -ne 0 ]
  done

  docker_stop ${syscont}
}

# Testcase #9.
#
# Within an inner mount namespace, ensure that a read-write immutable mount
# *can* be masked by a new read-only mount on top of it.
@test "ro mount on top of immutable rw mount -- unshare(mnt) + chroot()" {
  if [[ $skipTest -eq 1 ]]; then
    skip
  fi
  local_rootfs_prepare

  local syscont=$(docker_run --rm -v ${immutable_ro_dir_path}:${immutable_ro_dir_path}:ro -v ${immutable_ro_file_path}:${immutable_ro_file_path}:ro --mount type=tmpfs,destination=${immutable_masked_dir_path} -v /dev/null:${immutable_masked_file_path} ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)
  
  docker exec -d ${syscont} sh -c "unshare -m bash -c \"sleep 1000\""
  [ "$status" -eq 0 ]

  docker exec ${syscont} sh -c "pidof sleep"
  [ "$status" -eq 0 ]
  local inner_pid=$output

  chroot_prepare_nsenter ${syscont} ${inner_pid} ${chrootpath}  
  
  local immutable_rw_mounts=$(list_container_rw_mounts ${syscont} ${inner_pid} ${chrootpath})
  run empty_list ${immutable_rw_mounts}
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
    docker exec ${syscont} bash -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} bash -c \"[[ ! -d ${m} ]]\""
    if [ "$status" -eq 0 ]; then
      continue
    fi

    # This should pass (mount is read-write)
    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} touch ${m}"
    [ "$status" -eq 0 ]

    printf "\nmounting tmpfs (ro) on top of immutable rw mount ${m}\n"

    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} mount -t tmpfs -o ro,size=100M tmpfs ${m}"
    [ "$status" -eq 0 ]

    # This should fail (tmpfs mount is read-only)
    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} touch ${m}"
    [ "$status" -ne 0 ]

    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} umount ${m}"
    [ "$status" -eq 0 ]

    # This should pass (mount is read-write)
    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} touch ${m}"
    [ "$status" -eq 0 ]
  done

  docker_stop ${syscont}
}

# Testcase #10.
@test "unmount chain of file bind-mounts -- unshare(mnt) + chroot()" {
  if [[ $skipTest -eq 1 ]]; then
    skip
  fi
  local_rootfs_prepare

  local syscont=$(docker_run --rm -v ${immutable_ro_dir_path}:${immutable_ro_dir_path}:ro -v ${immutable_ro_file_path}:${immutable_ro_file_path}:ro --mount type=tmpfs,destination=${immutable_masked_dir_path} -v /dev/null:${immutable_masked_file_path} ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)
  
  docker exec -d ${syscont} sh -c "unshare -m bash -c \"sleep 1000\""
  [ "$status" -eq 0 ]

  docker exec ${syscont} sh -c "pidof sleep"
  [ "$status" -eq 0 ]
  local inner_pid=$output

  chroot_prepare_nsenter ${syscont} ${inner_pid} ${chrootpath}

  local immutable_mounts=$(list_container_mounts ${syscont} ${inner_pid} ${chrootpath})
  run empty_list ${immutable_mounts}
  [ "$status" -ne 0 ]  

  for m in ${immutable_mounts}; do
    # Skip /proc and /sys since these are special mounts (we have dedicated
    # tests that cover unmounting ops).
    if [[ ${m} =~ "/proc" ]] || [[ ${m} =~ "/proc/*" ]] ||
        [[ ${m} =~ "/sys" ]] || [[ ${m} =~ "/sys/*" ]]; then
      continue
    fi

    # Skip directory mountpoints.
    docker exec ${syscont} bash -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} bash -c \"[[ -d ${m} ]]\""
    if [ "$status" -eq 0 ]; then
      continue
    fi

    #
    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} touch ${m}2"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} mount -o bind ${m} ${m}2"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} umount ${m}2"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} umount ${m}"
    [ "$status" -ne 0 ]

  done

  docker_stop ${syscont}
}

# Testcase #11.
@test "unmount chain of dir bind-mounts -- unshare(mnt) + chroot()" {
  if [[ $skipTest -eq 1 ]]; then
    skip
  fi
  local_rootfs_prepare

  local syscont=$(docker_run --rm -v ${immutable_ro_dir_path}:${immutable_ro_dir_path}:ro -v ${immutable_ro_file_path}:${immutable_ro_file_path}:ro --mount type=tmpfs,destination=${immutable_masked_dir_path} -v /dev/null:${immutable_masked_file_path} ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)
  
  docker exec -d ${syscont} sh -c "unshare -m bash -c \"sleep 1000\""
  [ "$status" -eq 0 ]

  docker exec ${syscont} sh -c "pidof sleep"
  [ "$status" -eq 0 ]
  local inner_pid=$output

  chroot_prepare_nsenter ${syscont} ${inner_pid} ${chrootpath}

  local immutable_mounts=$(list_container_mounts ${syscont} ${inner_pid} ${chrootpath})
  run empty_list ${immutable_mounts}
  [ "$status" -ne 0 ]  

  for m in ${immutable_mounts}; do
    # Skip /proc and /sys since these are special mounts (we have dedicated
    # tests that cover unmounting ops).
    if [[ ${m} =~ "/proc" ]] || [[ ${m} =~ "/proc/*" ]] ||
        [[ ${m} =~ "/sys" ]] || [[ ${m} =~ "/sys/*" ]]; then
      continue
    fi

    # Skip file mountpoints.
    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} bash -c \"[[ ! -d ${m} ]]\""
    if [ "$status" -eq 0 ]; then
      continue
    fi

    # Create bind-mount and verify that only the first unmount is allowed.
    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} mount -t tmpfs -o ro,size=100M tmpfs ${m}"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} mount -t tmpfs -o ro,size=100M tmpfs ${m}"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} umount ${m}"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} umount ${m}"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} umount ${m}"
    [ "$status" -ne 0 ]

    # Create chained bind-mounts and verify that only the first two unmounts
    # are allowed.
    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} mkdir -p ${m}2 ${m}3"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} mount -o bind ${m} ${m}2"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} mount -o bind ${m}2 ${m}3"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} umount ${m}3"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} umount ${m}2"
    [ "$status" -eq 0 ]

    docker exec ${syscont} sh -c \
      "nsenter -a -t ${inner_pid} chroot ${chrootpath} umount ${m}"
    [ "$status" -ne 0 ]
  done

  docker_stop ${syscont}
}
