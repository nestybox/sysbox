#!/usr/bin/env bats

#
# Verify sys container mounts setup by the sysbox-mgr
#

load ../helpers/run
load ../helpers/fs
load ../helpers/docker
load ../helpers/sysbox-health

# verify sys container has a mount for /lib/modules/<kernel>
@test "kernel lib-module mount" {

  local kernel_rel=$(uname -r)
  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont" sh -c "mount | grep \"/lib/modules/${kernel_rel}\""
  [ "$status" -eq 0 ]

  if [ -n "$SHIFT_UIDS" ]; then
    [[ "$output" =~ "/lib/modules/${kernel_rel} on /lib/modules/${kernel_rel} type shiftfs".+"ro".+"relatime" ]]
  else
    [[ "$output" =~ "on /lib/modules/${kernel_rel}".+"ro".+"relatime" ]]
  fi

  docker_stop "$syscont"
}

# Verify that Ubuntu sys container has kernel-headers in the expected path.
@test "kernel headers mounts (ubuntu)" {

  local kernel_rel=$(uname -r)
  local distro=$(get_host_distro)

  local syscont=$(docker_run --rm ubuntu:bionic tail -f /dev/null)

  # Expected behavior will vary depending on the linux-distro running on the
  # host (i.e. test-priv container).
  if [[ "${distro}" == "centos" ]] ||
      [[ "${distro}" == "fedora" ]] ||
      [[ "${distro}" == "redhat" ]]; then

      docker exec "$syscont" sh -c "mount | grep \"/usr/src/kernels/${kernel_rel}\""
      [ "$status" -eq 0 ]

      if [ -n "$SHIFT_UIDS" ]; then
         [[ "${lines[0]}" =~ "/usr/src/kernels/${kernel_rel} on /usr/src/kernels/${kernel_rel} type shiftfs".+"ro".+"relatime" ]]
      else
        [[ "${lines[0]}" =~ "on /usr/src/kernels/${kernel_rel}".+"ro".+"relatime" ]]
      fi

      # Verify that /usr/src/linux-headers-$kernel_rel --> /usr/src/kernels/$kernel_rel
      # softlink has been created in ubuntu's kernel-headers expected path.
      docker exec "$syscont" sh -c "stat /usr/src/linux-headers-${kernel_rel} | egrep -q \"symbolic\""
      [ "$status" -eq 0 ]

 else
      docker exec "$syscont" sh -c "mount | grep \"/usr/src/linux-headers-${kernel_rel}\""
      [ "$status" -eq 0 ]

      if [ -n "$SHIFT_UIDS" ]; then
         [[ "${lines[0]}" =~ "/usr/src/linux-headers-${kernel_rel} on /usr/src/linux-headers-${kernel_rel} type shiftfs".+"ro".+"relatime" ]]
      else
        [[ "${lines[0]}" =~ "on /usr/src/linux-headers-${kernel_rel}".+"ro".+"relatime" ]]
      fi

      # Verify that no /usr/src/linux-headers-$kernel_rel --> /usr/src/kernels/$kernel_rel
      # softlink has been created -- it's not needed in this case as sysbox-runc/mgr
      # already bind-mounts all the required paths.
      docker exec "$syscont" sh -c "stat /usr/src/linux-headers-${kernel_rel} | egrep -q \"symbolic\""
      [ "$status" -eq 1 ]
  fi

  docker_stop "$syscont"
}

# Verify that Fedora sys container has kernel-headers in the expected path.
@test "kernel headers mounts (fedora)" {

  local kernel_rel=$(uname -r)
  local distro=$(get_host_distro)

  local syscont=$(docker_run --rm fedora:31 tail -f /dev/null)

  # Expected behavior will vary depending on the linux-distro running on the
  # host (i.e. test-priv container).
  if [[ "${distro}" == "centos" ]] ||
      [[ "${distro}" == "fedora" ]] ||
      [[ "${distro}" == "redhat" ]]; then

      docker exec "$syscont" sh -c "mount | grep \"/usr/src/kernels/${kernel_rel}\""
      [ "$status" -eq 0 ]

      if [ -n "$SHIFT_UIDS" ]; then
        [[ "${lines[0]}" =~ "/usr/src/kernels/${kernel_rel} on /usr/src/kernels/${kernel_rel} type shiftfs".+"ro".+"relatime" ]]
      else
        [[ "${lines[0]}" =~ "on /usr/src/kernels/${kernel_rel}".+"ro".+"relatime" ]]
      fi

      # Verify that no /usr/src/linux-headers-$kernel_rel --> /usr/src/kernels/$kernel_rel
      # softlink has been created -- it's not needed in this case as sysbox-runc/mgr
      # already bind-mounts all the required paths.
      docker exec "$syscont" sh -c "stat /usr/src/linux-headers-${kernel_rel} | egrep -q \"symbolic\""
      [ "$status" -eq 1 ]

 else
      docker exec "$syscont" sh -c "mount | grep \"/usr/src/linux-headers-${kernel_rel}\""
      [ "$status" -eq 0 ]

      if [ -n "$SHIFT_UIDS" ]; then
         [[ "${lines[0]}" =~ "/usr/src/linux-headers-${kernel_rel} on /usr/src/linux-headers-${kernel_rel} type shiftfs".+"ro".+"relatime" ]]
      else
        [[ "${lines[0]}" =~ "on /usr/src/linux-headers-${kernel_rel}".+"ro".+"relatime" ]]
      fi

      # Verify that /usr/src/kernels/linux-headers-$kernel_rel --> /usr/src/kernels/$kernel_rel
      # softlink has been created in fedora's kernel-headers expected path).
      docker exec "$syscont" sh -c "stat /usr/src/kernels/${kernel_rel} | egrep -q \"symbolic\""
      [ "$status" -eq 0 ]
  fi

  docker_stop "$syscont"
}

@test "chown bind mount special dir" {

  if [ -z "$SHIFT_UIDS" ]; then
    skip "needs UID shifting"
  fi

  local syscont
  local uid
  local gid

  # verify that sysbox-mgr chown's the ownership of a host dir mounted
  # into /var/lib/docker, to match the host uid:gid of the container's
  # root user.

  local mnt_src="/mnt/scratch/docker"
  local mnt_dst="/var/lib/docker"

  rm -rf $mnt_src
  mkdir $mnt_src

  orig_mnt_src_uid=$(stat -c "%u" $mnt_src)
  orig_mnt_src_gid=$(stat -c "%g" $mnt_src)

  # verify chown is applied when container starts
  syscont=$(docker_run --rm -v $mnt_src:$mnt_dst ${CTR_IMG_REPO}/alpine-docker-dbg tail -f /dev/null)

  uid=$(docker_root_uid_map $syscont)
  gid=$(docker_root_gid_map $syscont)

  mnt_src_uid=$(stat -c "%u" $mnt_src)
  mnt_src_gid=$(stat -c "%g" $mnt_src)

  echo "uid=$uid"
  echo "gid=$gid"
  echo "mnt_src_uid=$mnt_src_uid"
  echo "mnt_src_gid=$mnt_src_gid"

  [ "$uid" -eq "$mnt_src_uid" ]
  [ "$gid" -eq "$mnt_src_gid" ]

  # verify chown is reverted when container stops
  docker_stop "$syscont"

  mnt_src_uid=$(stat -c "%u" $mnt_src)
  mnt_src_gid=$(stat -c "%g" $mnt_src)

  [ "$mnt_src_uid" -eq "$orig_mnt_src_uid" ]
  [ "$mnt_src_gid" -eq "$orig_mnt_src_gid" ]

  rm -rf $mnt_src
}

@test "skip chown bind mount special dir" {

  if [ -z "$SHIFT_UIDS" ]; then
    skip "needs UID shifting"
  fi

  local syscont
  local uid
  local gid

  # verify that sysbox-mgr skips changing the ownership of a host dir
  # mounted into /var/lib/docker if the host dir and first-level subdirs
  # match the container's root user uid:gid

  local mnt_src="/mnt/scratch/docker"
  local mnt_dst="/var/lib/docker"

  rm -rf $mnt_src
  mkdir -p $mnt_src/sub1/sub2

  local sysbox_subid=$(grep sysbox /etc/subuid | cut -d":" -f2)

  chown $sysbox_subid:$sysbox_subid $mnt_src $mnt_src/sub1

  # verify chown is skipped when container starts
  syscont=$(docker_run --rm -v $mnt_src:$mnt_dst ${CTR_IMG_REPO}/alpine-docker-dbg tail -f /dev/null)

  sub2_uid=$(stat -c "%u" $mnt_src/sub1/sub2)
  sub2_gid=$(stat -c "%g" $mnt_src/sub1/sub2)

  [ "$sub2_uid" -ne "$sysbox_subid" ]
  [ "$sub2_gid" -ne "$sysbox_subid" ]

  # verify chown revert is skipped when container stops
  docker_stop "$syscont"

  sub2_uid=$(stat -c "%u" $mnt_src/sub1/sub2)
  sub2_gid=$(stat -c "%g" $mnt_src/sub1/sub2)

  [ "$sub2_uid" -ne "$sysbox_subid" ]
  [ "$sub2_gid" -ne "$sysbox_subid" ]

  rm -rf $mnt_src
}
