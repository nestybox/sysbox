#!/usr/bin/env bats

#
# Verify trapping & emulation on "mount" and "unmount2" syscalls
#

load ../helpers/run
load ../helpers/syscall
load ../helpers/docker
load ../helpers/environment
load ../helpers/mounts
load ../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

#
# Test to verify common mount syscall checks performed by sysbox
#

# Verify that mount syscall emulation performs correct path resolution (per path_resolution(7))
@test "mount path-resolution" {

  # TODO: test chmod dir permissions & path-resolution

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  local mnt_path=/root/l1/l2/proc

  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  # absolute path
  docker exec "$syscont" bash -c "mount -t proc proc $mnt_path"
  [ "$status" -eq 0 ]
  verify_syscont_procfs_mnt $syscont $mnt_path
  docker exec "$syscont" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  # relative path
  docker exec "$syscont" bash -c "cd /root/l1 && mount -t proc proc l2/proc"
  [ "$status" -eq 0 ]
  verify_syscont_procfs_mnt $syscont $mnt_path
  docker exec "$syscont" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  # .. in path
  docker exec "$syscont" bash -c "cd /root/l1/l2 && mount -t proc proc ../../../root/l1/l2/proc"
  [ "$status" -eq 0 ]
  verify_syscont_procfs_mnt $syscont $mnt_path
  docker exec "$syscont" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  # . in path
  docker exec "$syscont" bash -c "cd /root/l1/l2 && mount -t proc proc ./proc"
  [ "$status" -eq 0 ]
  verify_syscont_procfs_mnt $syscont $mnt_path
  docker exec "$syscont" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "cd $mnt_path && mount -t proc proc ."
  [ "$status" -eq 0 ]
  verify_syscont_procfs_mnt $syscont $mnt_path
  docker exec "$syscont" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  # relative symlink
  docker exec "$syscont" bash -c "cd /root && ln -s l1/l2 l2link"
  [ "$status" -eq 0 ]
  docker exec "$syscont" bash -c "cd /root && mount -t proc proc l2link/proc"
  [ "$status" -eq 0 ]
  verify_syscont_procfs_mnt $syscont $mnt_path
  docker exec "$syscont" bash -c "rm /root/l2link"
  [ "$status" -eq 0 ]
  docker exec "$syscont" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  # relative symlink at end
  docker exec "$syscont" bash -c "cd /root && ln -s l1/l2/proc proclink"
  [ "$status" -eq 0 ]
  docker exec "$syscont" bash -c "cd /root && mount -t proc proc proclink"
  [ "$status" -eq 0 ]
  verify_syscont_procfs_mnt $syscont $mnt_path
  docker exec "$syscont" bash -c "rm /root/proclink"
  [ "$status" -eq 0 ]
  docker exec "$syscont" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  # abs symlink
  docker exec "$syscont" bash -c "cd /root && ln -s /root/l1/l2/proc abslink"
  [ "$status" -eq 0 ]
  docker exec "$syscont" bash -c "cd /root && mount -t proc proc abslink"
  [ "$status" -eq 0 ]
  verify_syscont_procfs_mnt $syscont $mnt_path
  docker exec "$syscont" bash -c "rm /root/abslink"
  [ "$status" -eq 0 ]
  docker exec "$syscont" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  # invalid path
  docker exec "$syscont" bash -c "cd /root && mount -t proc proc invalidpath"
  [ "$status" -eq 255 ]
  [[ "$output" =~ "No such file or directory" ]]

  # TODO: overly long path (> MAXPATHLEN) returns in ENAMETOOLONG

  # TODO: mount syscall with empty mount path (should return ENOENT)
  # requires calling mount syscall directly

  docker_stop "$syscont"
}

# Verify that mount syscall emulation does correct permission checks
@test "mount permission checking" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/debian:latest tail -f /dev/null)
  local mnt_path=/root/l1/l2/proc

  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  # root user can mount
  docker exec "$syscont" bash -c "mount -t proc proc $mnt_path"
  [ "$status" -eq 0 ]
  verify_syscont_procfs_mnt $syscont $mnt_path

  docker exec "$syscont" bash -c "umount $mnt_path"
  [ "$status" -eq 0 ]

  # a non-root user can't mount (needs cap_sys_admin)
  docker exec "$syscont" bash -c "useradd -m -u 1000 someone"
  [ "$status" -eq 0 ]

  docker exec -u 1000:1000 "$syscont" bash -c "mkdir -p /home/someone/l1/l2/proc && mount -t proc proc /home/someone/l1/l2/proc"
  [ "$status" -eq 1 ]

  docker_stop "$syscont"
}

# Verify that mount syscall emulation does correct capability checks
@test "mount capability checking" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/debian:latest tail -f /dev/null)
  local mnt_path=/root/l1/l2/proc

  docker exec "$syscont" bash -c "mkdir -p $mnt_path"
  [ "$status" -eq 0 ]

  # root user without CAP_SYS_ADMIN can't mount
  docker exec "$syscont" bash -c "capsh --inh=\"\" --drop=cap_sys_admin -- -c \"mount -t proc proc $mnt_path\""
  [ "$status" -ne 0 ]

  # root user without CAP_DAC_OVERRIDE, CAP_DAC_READ_SEARCH can't mount if path is non-searchable
  docker exec "$syscont" bash -c "chmod 400 /root/l1"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "capsh --inh=\"\" --drop=cap_dac_override,cap_dac_read_search -- -c \"mount -t proc proc $mnt_path\""
  [ "$status" -ne 0 ]

  # a non-root user with appropriate caps can perform the mount; we use the
  # mountProcDac program to obtain these caps.

  make -C "$SYSBOX_ROOT/tests/scr/capRaise"

  docker exec "$syscont" bash -c "useradd -u 1000 someone"
  [ "$status" -eq 0 ]

   # copy mountProcDac program and set file caps on it
  docker cp "$SYSBOX_ROOT/tests/scr/capRaise/mountProcDac" "$syscont:/usr/bin"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "chown someone:someone /usr/bin/mountProcDac"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c 'setcap "cap_sys_admin,cap_dac_read_search,cap_dac_override=p" /usr/bin/mountProcDac'
  [ "$status" -eq 0 ]

  # perform the mount with mountProcDac
  docker exec -u 1000:1000 "$syscont" bash -c "mountProcDac $mnt_path"
  [ "$status" -eq 0 ]

  docker_stop "$syscont"
}

#
# Test to verify sys container immutable mounts.
#
# Note: a sys container immutable mount is a mount that is setup at container
# creation time.
#

# Ensure immutable mounts can't be unmounted from inside the container
@test "immutable mount can't be unmounted" {

  local syscont=$(docker_run --rm debian:latest tail -f /dev/null)
  local immutable_mounts=$(list_container_mounts $syscont)

  for m in $immutable_mounts; do
    printf "\ntesting unmount of immutable mount $m\n"

    docker exec "$syscont" sh -c "umount $m"
    [ "$status" -ne 0 ]
  done

  local immutable_mounts_after=$(list_container_mounts $syscont)
  [[ $immutable_ro_mounts == $immutable_ro_mounts_after ]]

  docker_stop "$syscont"
}

# Ensure that a read-only immutable mount can't be remounted as read-write
# inside the container.
@test "immutable ro mount can't be remounted rw" {

  local syscont=$(docker_run --rm debian:latest tail -f /dev/null)
  local immutable_ro_mounts=$(list_container_ro_mounts $syscont)

  for m in $immutable_ro_mounts; do
    printf "\ntesting rw remount of immutable ro mount $m\n"

    docker exec "$syscont" sh -c "mount -o remount,bind,rw $m"
    [ "$status" -ne 0 ]
  done

  local immutable_ro_mounts_after=$(list_container_ro_mounts $syscont)
  [[ $immutable_ro_mounts == $immutable_ro_mounts_after ]]

  docker_stop "$syscont"
}

# Ensure that a read-write immutable mount *can* be remounted as read-only inside
# the container.
@test "immutable rw mount can be remounted ro" {

  local syscont=$(docker_run --rm debian:latest tail -f /dev/null)
  local immutable_rw_mounts=$(list_container_rw_mounts $syscont)

  for m in $immutable_rw_mounts; do

    # Remounting /proc or /dev as read-only will prevent docker execs into the
    # container; skip these.
    if [[ $m =~ "/proc" ]] || [[ $m =~ "/proc/*" ]] ||
       [[ $m =~ "/dev" ]] || [[ $m =~ "/dev/*" ]]; then
      continue
    fi

    printf "\ntesting ro remount of immutable rw mount $m\n"

    docker exec "$syscont" sh -c "mount -o remount,bind,ro $m"
    [ "$status" -eq 0 ]
  done

  docker_stop "$syscont"
}

# Ensure that a read-only immutable mount *can* be remounted as read-only inside
# the container.
@test "immutable ro mount can be remounted ro" {

  local syscont=$(docker_run --rm debian:latest tail -f /dev/null)
  local immutable_ro_mounts=$(list_container_ro_mounts $syscont)

  for m in $immutable_ro_mounts; do
    printf "\ntesting ro remount of immutable ro mount $m\n"

    docker exec "$syscont" sh -c "mount -o remount,bind,ro $m"
    [ "$status" -eq 0 ]
  done

  local immutable_ro_mounts_after=$(list_container_ro_mounts $syscont)
  [[ $immutable_ro_mounts == $immutable_ro_mounts_after ]]

  docker_stop "$syscont"
}

# Ensure that a read-write immutable mount *can* be remounted as read-write or
# read-only inside the container.
@test "immutable rw mount can be remounted rw" {

  local syscont=$(docker_run --rm debian:latest tail -f /dev/null)
  local immutable_rw_mounts=$(list_container_rw_mounts $syscont)

  for m in $immutable_rw_mounts; do
    printf "\ntesting rw remount of immutable rw mount $m\n"

    docker exec "$syscont" sh -c "mount -o remount,bind,rw $m"
    [ "$status" -eq 0 ]
  done

  local immutable_rw_mounts_after=$(list_container_rw_mounts $syscont)
  [[ $immutable_rw_mounts == $immutable_rw_mounts_after ]]

  docker_stop "$syscont"
}

# Ensure that a read-only immutable mount can't be bind-mounted
# to a new mountpoint then re-mounted read-write
@test "immutable ro mount can't be bind-mounted rw" {

  local syscont=$(docker_run --rm debian:latest tail -f /dev/null)
  local immutable_ro_mounts=$(list_container_ro_mounts $syscont)
  local target=/root/target

  for m in $immutable_ro_mounts; do

    printf "\ntesting bind-mount of immutable ro bind-mount $m -> $target\n"

    # Create bind-mount target (dir or file, depending on bind-mount source type)
    docker exec "$syscont" bash -c "[[ -d $m ]]"

    if [ "$status" -eq 0 ]; then
      docker exec "$syscont" sh -c "mkdir -p $target"
      [ "$status" -eq 0 ]
    else
      docker exec "$syscont" sh -c "touch $target"
      [ "$status" -eq 0 ]
    fi

    docker exec "$syscont" sh -c "mount --bind $m $target"
    [ "$status" -eq 0 ]

    # Verify the bind-mount continues to be read-only
    docker exec "$syscont" sh -c "touch $target"
    [ "$status" -ne 0 ]

    # This rw remount should fail
    printf "\ntesting rw remount of immutable ro bind-mount $target\n"
    docker exec "$syscont" sh -c "mount -o remount,bind,rw $target"
    [ "$status" -ne 0 ]

    # This ro remount should pass (it's not needed but just to double-check)
    docker exec "$syscont" sh -c "mount -o remount,bind,ro $target"
    [ "$status" -eq 0 ]

    docker exec "$syscont" sh -c "umount $target"
    [ "$status" -eq 0 ]

    docker exec "$syscont" sh -c "rm -rf $target"
    [ "$status" -eq 0 ]
  done

  docker_stop "$syscont"
}

# Ensure that a read-write immutable mount can be bind-mounted
# to a new mountpoint then re-mounted read-only
@test "immutable rw mount can be bind-mounted ro" {

  local syscont=$(docker_run --rm debian:latest tail -f /dev/null)
  local immutable_rw_mounts=$(list_container_rw_mounts $syscont)
  local target=/root/target

  for m in $immutable_rw_mounts; do

    # skip /proc and /sys since these are special mounts (we have dedicated
    # tests for remounting them). We also
    if [[ $m =~ "/proc" ]] || [[ $m =~ "/proc/*" ]] ||
       [[ $m =~ "/sys" ]] || [[ $m =~ "/sys/*" ]] ||
       [[ $m =~ "/dev" ]] || [[ $m =~ "/dev/*" ]]; then
      continue
    fi

    printf "\ntesting bind-mount of immutable rw bind-mount $m -> $target\n"

    # Create bind-mount target (dir or file, depending on bind-mount source type)
    docker exec "$syscont" bash -c "[[ -d $m ]]"

    if [ "$status" -eq 0 ]; then
      docker exec "$syscont" sh -c "mkdir -p $target"
      [ "$status" -eq 0 ]
    else
      docker exec "$syscont" sh -c "touch $target"
      [ "$status" -eq 0 ]
    fi

    docker exec "$syscont" sh -c "mount --bind $m $target"
    [ "$status" -eq 0 ]

    # Verify the bind-mount continues to be read-write
    docker exec "$syscont" sh -c "touch $target"
    [ "$status" -eq 0 ]

    # This ro remount should pass
    printf "\ntesting ro remount of immutable rw bind-mount $target\n"
    docker exec "$syscont" sh -c "mount -o remount,bind,ro $target"
    [ "$status" -eq 0 ]

    # Verify the bind-mount is now read-only
    docker exec "$syscont" sh -c "touch $target"
    [ "$status" -ne 0 ]

    # Verify the bind-mount source continues to be read-write
    docker exec "$syscont" sh -c "touch $m"
    [ "$status" -eq 0 ]

    # This rw remount should also pass
    docker exec "$syscont" sh -c "mount -o remount,bind,rw $target"
    [ "$status" -eq 0 ]

    docker exec "$syscont" sh -c "umount $target"
    [ "$status" -eq 0 ]

    docker exec "$syscont" sh -c "rm -rf $target"
    [ "$status" -eq 0 ]
  done

  docker_stop "$syscont"
}

# Ensure that a read-only immutable mount *can* be masked by
# a new read-write mount on top of it.
@test "rw mount on top of immutable ro mount" {

  local syscont=$(docker_run --rm debian:latest tail -f /dev/null)
  local immutable_ro_mounts=$(list_container_ro_mounts $syscont)

  for m in $immutable_ro_mounts; do

    # skip /proc and /sys since these are special mounts (we have dedicated
    # tests for remounting them). We also
    if [[ $m =~ "/proc" ]] || [[ $m =~ "/proc/*" ]] ||
         [[ $m =~ "/sys" ]] || [[ $m =~ "/sys/*" ]] ||
         [[ $m =~ "/dev" ]] || [[ $m =~ "/dev/*" ]]; then
      continue
    fi

    # This should fail (mount is read-only)
    docker exec "$syscont" sh -c "touch $m"
    [ "$status" -ne 0 ]

    printf "\nmounting tmpfs (rw) on top of immutable ro mount $m\n"

    docker exec "$syscont" sh -c "mount -t tmpfs -o size=100M tmpfs $m"
    [ "$status" -eq 0 ]

    # This should pass (tmpfs mount is read-write)
    docker exec "$syscont" sh -c "touch $m"
    [ "$status" -eq 0 ]

    docker exec "$syscont" sh -c "umount $m"
    [ "$status" -eq 0 ]

    # This should fail (mount is read-only)
    docker exec "$syscont" sh -c "touch $m"
    [ "$status" -ne 0 ]
  done

  docker_stop "$syscont"
}

# Ensure that a read-write immutable mount *can* be masked by
# a new read-only mount on top of it.
@test "ro mount on top of immutable rw mount" {

  local syscont=$(docker_run --rm debian:latest tail -f /dev/null)
  local immutable_rw_mounts=$(list_container_rw_mounts $syscont)

  for m in $immutable_rw_mounts; do

    # skip /proc and /sys since these are special mounts (we have dedicated
    # tests for remounting them). We also
    if [[ $m =~ "/proc" ]] || [[ $m =~ "/proc/*" ]] ||
         [[ $m =~ "/sys" ]] || [[ $m =~ "/sys/*" ]] ||
         [[ $m =~ "/dev" ]] || [[ $m =~ "/dev/*" ]]; then
      continue
    fi

    # This should pass (mount is read-write)
    docker exec "$syscont" sh -c "touch $m"
    [ "$status" -eq 0 ]

    printf "\nmounting tmpfs (ro) on top of immutable rw mount $m\n"

    docker exec "$syscont" sh -c "mount -t tmpfs -o ro,size=100M tmpfs $m"
    [ "$status" -eq 0 ]

    # This should fail (tmpfs mount is read-only)
    docker exec "$syscont" sh -c "touch $m"
    [ "$status" -ne 0 ]

    docker exec "$syscont" sh -c "umount $m"
    [ "$status" -eq 0 ]

    # This should pass (mount is read-write)
    docker exec "$syscont" sh -c "touch $m"
    [ "$status" -eq 0 ]
  done

  docker_stop "$syscont"
}

@test "immutable ro mount in inner mnt ns" {

  local syscont=$(docker_run --rm debian:latest tail -f /dev/null)
  local immutable_ro_mounts=$(list_container_ro_mounts $syscont)

  docker exec -d "$syscont" sh -c "unshare -m bash -c \"sleep 1000\""
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "pidof sleep"
  [ "$status" -eq 0 ]
  inner_pid=$output

  for m in $immutable_ro_mounts; do
    docker exec "$syscont" sh -c "nsenter -a -t $inner_pid umount $m"
    [ "$status" -ne 0 ]

    docker exec "$syscont" sh -c "nsenter -a -t $inner_pid mount -o remount,bind,rw $m"
    [ "$status" -ne 0 ]
  done

  docker_stop "$syscont"
}

@test "immutable ro mount in inner container" {

  local syscont=$(docker_run --rm nestybox/alpine-docker-dbg tail -f /dev/null)
  local immutable_ro_mounts=$(list_container_ro_mounts $syscont)
  local linux_libmod_mount=$(echo $immutable_ro_mounts |  tr ' ' '\n' | grep "lib/modules")

  [ -n "$linux_libmod_mount" ]

  docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont

  docker exec "$syscont" sh -c "docker run -d --name inner -v $linux_libmod_mount:$linux_libmod_mount:rw debian tail -f /dev/null"
  [ "$status" -eq 0 ]

  # This should fail (libmod mount is read-only inside inner container)
  docker exec "$syscont" sh -c "docker exec inner sh -c \"touch $linux_libmod_mount\""
  [ "$status" -ne 0 ]

  docker exec "$syscont" sh -c "docker stop -t0 inner"
  [ "$status" -eq 0 ]

  docker_stop "$syscont"
}

@test "immutable ro mount in inner priv container" {

  local syscont=$(docker_run --rm nestybox/alpine-docker-dbg tail -f /dev/null)
  local immutable_ro_mounts=$(list_container_ro_mounts $syscont)
  local linux_libmod_mount=$(echo $immutable_ro_mounts |  tr ' ' '\n' | grep "lib/modules")

  [ -n "$linux_libmod_mount" ]

  docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont

  docker exec "$syscont" sh -c "docker run --privileged -d --name inner -v $linux_libmod_mount:$linux_libmod_mount debian tail -f /dev/null"
  [ "$status" -eq 0 ]

  # This should fail (libmod mount is read-only inside inner container)
  docker exec "$syscont" sh -c "docker exec inner sh -c \"touch $linux_libmod_mount\""
  [ "$status" -ne 0 ]

  # This should also fail (can't remount a sysbox immutable mount from inside an inner priv container)
  docker exec "$syscont" sh -c "docker exec inner sh -c \"mount -o remount,bind,rw $linux_libmod_mount\""
  [ "$status" -ne 0 ]

  docker exec "$syscont" sh -c "docker stop -t0 inner"
  [ "$status" -eq 0 ]

  docker_stop "$syscont"
}

@test "immutable rw mount in inner container" {

  local mnt=/root/dummy
  mkdir -p $mnt

  if [ -z "$SHIFT_UIDS" ]; then
    subid=$(grep sysbox /etc/subuid | cut -d":" -f2)
    chown -R $subid:$subid $mnt
  fi

  local syscont=$(docker_run --rm -v $mnt:$mnt nestybox/alpine-docker-dbg tail -f /dev/null)

  docker exec -d "$syscont" sh -c "touch $mnt"
  [ "$status" -eq 0 ]

  docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont

  docker exec "$syscont" sh -c "docker run --rm -d --name inner -v $mnt:$mnt:rw debian tail -f /dev/null"
  [ "$status" -eq 0 ]

  # This should pass (mount is read-write inside inner container)
  docker exec "$syscont" sh -c "docker exec inner sh -c \"touch $mnt\""
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker stop -t0 inner"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker run --rm -d --name inner -v $mnt:$mnt:ro debian tail -f /dev/null"
  [ "$status" -eq 0 ]

  # This should fail (mount is read-only inside inner container)
  docker exec "$syscont" sh -c "docker exec inner sh -c \"touch $mnt\""
  [ "$status" -ne 0 ]

  docker exec "$syscont" sh -c "docker stop -t0 inner"
  [ "$status" -eq 0 ]

  docker_stop "$syscont"
}

@test "don't confuse inner priv container mount with immutable mount" {

  local syscont=$(docker_run --rm nestybox/alpine-docker-dbg tail -f /dev/null)
  local immutable_ro_mounts=$(list_container_ro_mounts $syscont)
  local linux_libmod_mount=$(echo $immutable_ro_mounts |  tr ' ' '\n' | grep "lib/modules")

  [ -n "$linux_libmod_mount" ]

  docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont

  docker exec "$syscont" sh -c "docker run --privileged -d --name inner debian tail -f /dev/null"
  [ "$status" -eq 0 ]

  # In the inner container, create a dir and mountpoint whose name matches that
  # of an immutable sysbox mount
  docker exec "$syscont" sh -c "docker exec inner sh -c \"mkdir -p $linux_libmod_mount\""
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker exec inner sh -c \"mount --bind $linux_libmod_mount $linux_libmod_mount\""
  [ "$status" -eq 0 ]

  # Verify we can write, remount, and umount the newly created mountpoint without problem
  docker exec "$syscont" sh -c "docker exec inner sh -c \"touch $linux_libmod_mount\""
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker exec inner sh -c \"mount -o remount,bind,ro $linux_libmod_mount\""
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker exec inner sh -c \"mount -o remount,bind,rw $linux_libmod_mount\""
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker exec inner sh -c \"umount $linux_libmod_mount\""
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker stop -t0 inner"
  [ "$status" -eq 0 ]

  docker_stop "$syscont"
}
