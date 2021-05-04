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

# verify sys container mount for /lib/modules/<kernel> is still there after a container restart
@test "kernel lib-module mount survives restart" {

  local kernel_rel=$(uname -r)
  local syscont=$(docker_run ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker_stop "$syscont"

  docker start "$syscont"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "mount | grep \"/lib/modules/${kernel_rel}\""
  [ "$status" -eq 0 ]

  if [ -n "$SHIFT_UIDS" ]; then
    [[ "$output" =~ "/lib/modules/${kernel_rel} on /lib/modules/${kernel_rel} type shiftfs".+"ro".+"relatime" ]]
  else
    [[ "$output" =~ "on /lib/modules/${kernel_rel}".+"ro".+"relatime" ]]
  fi

  docker_stop "$syscont"

  docker rm "$syscont"
  [ "$status" -eq 0 ]
}

# Verify that Ubuntu sys container has kernel-headers in the expected path.
@test "kernel headers mounts (ubuntu)" {

  local kernel_rel=$(uname -r)
  local distro=$(get_host_distro)

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu:bionic tail -f /dev/null)

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

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/fedora:31 tail -f /dev/null)

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

@test "uid-shift bind mount special dir" {

  if [ -z "$SHIFT_UIDS" ]; then
    skip "needs UID shifting"
  fi

  local syscont
  local uid
  local gid

  # Verify that sysbox-mgr "shifts" the ownership of a host dir mounted
  # into /var/lib/docker, to match the host uid:gid of the container's
  # root user. The shifting is done via chown.

  local mnt_src="/mnt/scratch/docker"
  local mnt_dst="/var/lib/docker"

  rm -rf $mnt_src
  mkdir $mnt_src

  orig_mnt_src_uid=$(stat -c "%u" $mnt_src)
  orig_mnt_src_gid=$(stat -c "%g" $mnt_src)

  # Verify chown-based shifting is applied when container starts
  syscont=$(docker_run --rm -v $mnt_src:$mnt_dst ${CTR_IMG_REPO}/alpine-docker-dbg tail -f /dev/null)

  uid=$(docker_root_uid_map $syscont)
  gid=$(docker_root_gid_map $syscont)

  mnt_src_uid=$(stat -c "%u" $mnt_src)
  mnt_src_gid=$(stat -c "%g" $mnt_src)

  [ "$uid" -eq "$mnt_src_uid" ]
  [ "$gid" -eq "$mnt_src_gid" ]

  #
  # Have the container create some files on the special dir, with varying ownerships and types.
  #
  # The /var/lib/docker dir inside the container will have these files:
  #
  # -rw-r--r--    1 root     root             0 Apr 15 00:29 root-file
  # lrwxrwxrwx    1 root     root            25 Apr 15 00:29 root-file-symlink -> /var/lib/docker/root-file
  # lrwxrwxrwx    1 root     root            23 Apr 15 00:29 root-file-symlink-bad -> /var/lib/docker/no-file
  # -rw-r--r--    2 1000     1000             0 Apr 15 00:29 user-file
  # -rw-r--r--    2 1000     1000             0 Apr 15 00:29 user-file-hardlink
  # lrwxrwxrwx    1 1000     1000            25 Apr 15 00:29 user-file-symlink -> /var/lib/docker/user-file
  #
  # Later we will check if these get chowned correctly when the container is stopped and re-started.

  # root-owned file
  docker exec "$syscont" sh -c "touch $mnt_dst/root-file"
  [ "$status" -eq 0 ]

  # symlink to root-owned file
  docker exec "$syscont" sh -c "ln -s $mnt_dst/root-file $mnt_dst/root-file-symlink"
  [ "$status" -eq 0 ]

  # ACL on root-owned file
  docker exec "$syscont" sh -c "apk add acl"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "setfacl -m u:1000:rw,g:1001:r $mnt_dst/root-file"
  [ "$status" -eq 0 ]

  # dangling symlink
  docker exec "$syscont" sh -c "ln -s $mnt_dst/no-file $mnt_dst/root-file-symlink-bad"
  [ "$status" -eq 0 ]

  # user-owned file
  docker exec "$syscont" sh -c "touch $mnt_dst/user-file && chown 1000:1000 $mnt_dst/user-file"
  [ "$status" -eq 0 ]

  # symlink to user-owned file
  docker exec "$syscont" sh -c "ln -s $mnt_dst/user-file $mnt_dst/user-file-symlink && chown -h 1000:1000 $mnt_dst/user-file-symlink"
  [ "$status" -eq 0 ]

  # hardlink to user-owned file
  docker exec "$syscont" sh -c "ln $mnt_dst/user-file $mnt_dst/user-file-hardlink"
  [ "$status" -eq 0 ]

  #
  # verify the uid shifting is performed when container stops
  #
  docker_stop "$syscont"

  # mount dir
  mnt_src_uid=$(stat -c "%u" $mnt_src)
  mnt_src_gid=$(stat -c "%g" $mnt_src)
  [ "$mnt_src_uid" -eq "$orig_mnt_src_uid" ]
  [ "$mnt_src_gid" -eq "$orig_mnt_src_gid" ]

  # root-owned file
  file_uid=$(stat -c "%u" $mnt_src/root-file)
  file_gid=$(stat -c "%g" $mnt_src/root-file)
  [ "$file_uid" -eq 0 ]
  [ "$file_gid" -eq 0 ]

  # symlink to root-owned file
  file_uid=$(stat -c "%u" $mnt_src/root-file-symlink)
  file_gid=$(stat -c "%g" $mnt_src/root-file-symlink)
  [ "$file_uid" -eq 0 ]
  [ "$file_gid" -eq 0 ]

  # ACL on root-owned file
  run sh -c "getfacl -n --omit-header $mnt_src/root-file | grep 'user:1000:rw-'"
  [ "$status" -eq 0 ]
  run sh -c "getfacl -n --omit-header $mnt_src/root-file | grep 'group:1001:r--'"
  [ "$status" -eq 0 ]

  # dangling symlink
  file_uid=$(stat -c "%u" $mnt_src/root-file-symlink-bad)
  file_gid=$(stat -c "%g" $mnt_src/root-file-symlink-bad)
  [ "$file_uid" -eq 0 ]
  [ "$file_gid" -eq 0 ]

  # user-owned file
  file_uid=$(stat -c "%u" $mnt_src/user-file)
  file_gid=$(stat -c "%g" $mnt_src/user-file)
  [ "$file_uid" -eq 1000 ]
  [ "$file_gid" -eq 1000 ]

  # symlink to user-owned file
  file_uid=$(stat -c "%u" $mnt_src/user-file-symlink)
  file_gid=$(stat -c "%g" $mnt_src/user-file-symlink)
  [ "$file_uid" -eq 1000 ]
  [ "$file_gid" -eq 1000 ]

  # hardlink to user-owned file
  file_uid=$(stat -c "%u" $mnt_src/user-file-hardlink)
  file_gid=$(stat -c "%g" $mnt_src/user-file-hardlink)
  [ "$file_uid" -eq 1000 ]
  [ "$file_gid" -eq 1000 ]

  #
  # Create a new container with the same mount and verify ownership looks good
  #
  syscont=$(docker_run --rm -v $mnt_src:$mnt_dst ${CTR_IMG_REPO}/alpine-docker-dbg tail -f /dev/null)

  # root-owned file
  file_uid=$(__docker exec "$syscont" sh -c "stat -c \"%u\" $mnt_dst/root-file")
  file_gid=$(__docker exec "$syscont" sh -c "stat -c \"%g\" $mnt_dst/root-file")
  [ "$file_uid" -eq 0 ]
  [ "$file_gid" -eq 0 ]

  # symlink to root-owned file
  file_uid=$(__docker exec "$syscont" sh -c "stat -c \"%u\" $mnt_dst/root-file-symlink")
  file_gid=$(__docker exec "$syscont" sh -c "stat -c \"%g\" $mnt_dst/root-file-symlink")
  [ "$file_uid" -eq 0 ]
  [ "$file_gid" -eq 0 ]

  # ACL on root-owned file
  docker exec "$syscont" sh -c "apk add acl"
  [ "$status" -eq 0 ]
  docker exec "$syscont" sh -c "getfacl -n --omit-header $mnt_dst/root-file | grep 'user:1000:rw-'"
  [ "$status" -eq 0 ]
  docker exec "$syscont" sh -c "getfacl -n --omit-header $mnt_dst/root-file | grep 'group:1001:r--'"
  [ "$status" -eq 0 ]

  # dangling symlink
  file_uid=$(__docker exec "$syscont" sh -c "stat -c \"%u\" $mnt_dst/root-file-symlink-bad")
  file_gid=$(__docker exec "$syscont" sh -c "stat -c \"%g\" $mnt_dst/root-file-symlink-bad")
  [ "$file_uid" -eq 0 ]
  [ "$file_gid" -eq 0 ]

  # user-owned file
  file_uid=$(__docker exec "$syscont" sh -c "stat -c \"%u\" $mnt_dst/user-file")
  file_gid=$(__docker exec "$syscont" sh -c "stat -c \"%g\" $mnt_dst/user-file")
  [ "$file_uid" -eq 1000 ]
  [ "$file_gid" -eq 1000 ]

  # symlink to user-owned file
  file_uid=$(__docker exec "$syscont" sh -c "stat -c \"%u\" $mnt_dst/user-file-symlink")
  file_gid=$(__docker exec "$syscont" sh -c "stat -c \"%g\" $mnt_dst/user-file-symlink")
  [ "$file_uid" -eq 1000 ]
  [ "$file_gid" -eq 1000 ]

  # hardlink to user-owned file
  file_uid=$(__docker exec "$syscont" sh -c "stat -c \"%u\" $mnt_dst/user-file-hardlink")
  file_gid=$(__docker exec "$syscont" sh -c "stat -c \"%g\" $mnt_dst/user-file-hardlink")
  [ "$file_uid" -eq 1000 ]
  [ "$file_gid" -eq 1000 ]

  docker_stop "$syscont"

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
