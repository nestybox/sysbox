#!/usr/bin/env bats

#
# Verify sys container mounts setup by the sysbox-mgr
#

load ../helpers/run
load ../helpers/fs
load ../helpers/docker
load ../helpers/uid-shift
load ../helpers/sysbox-health

@test "mounts basic" {

	local mnt_src1="/mnt/scratch/test1"
	local mnt_src2="/mnt/scratch/test2"

	local mnt_dst1="/mnt"
	local mnt_dst2="/var/lib/docker"

	rm -rf $mnt_src1 $mnt_src2
	mkdir -p $mnt_src1 $mnt_src2

	syscont=$(docker_run --rm -v $mnt_src1:$mnt_dst1 -v $mnt_src2:$mnt_dst2 ${CTR_IMG_REPO}/alpine-docker-dbg tail -f /dev/null)

	docker exec "$syscont" sh -c "stat -c \"%u %g\" /home"
	[ "$status" -eq 0 ]
	[[ "$output" == "0 0" ]]

	# Verify rootfs uses idmapping or shiftfs or chown
	if sysbox_using_overlayfs_on_idmapped_mnt; then

		# We can't search for "idmapped" in the rootfs mount because it's the
		# overlayfs lower layers that are id-mapped, not the top layer. Rather we
		# check it's not shiftfs or chowned, which implies it's id-mapped as
		# otherwise the uid:gid check above would have failed.
		docker exec "$syscont" sh -c "findmnt | egrep \"^/\" | grep -v shiftfs"
		[ "$status" -eq 0 ]
		docker exec "$syscont" sh -c "findmnt | egrep \"^/\" | grep -v \"/var/lib/sysbox\""
		[ "$status" -eq 0 ]

	elif sysbox_using_shiftfs_on_overlayfs; then
		docker exec "$syscont" sh -c "findmnt | egrep \"^/\" | grep shiftfs"
		[ "$status" -eq 0 ]
	else
		docker exec "$syscont" sh -c "findmnt | egrep \"^/\" | grep \"/var/lib/sysbox\""
		[ "$status" -eq 0 ]
	fi

	# Verify implicit bind mounts use idmapping or shiftfs or chown
   local kernel_rel=$(uname -r)
	docker exec "$syscont" sh -c "mount | grep \"/lib/modules/${kernel_rel}\""
	[ "$status" -eq 0 ]

	if sysbox_using_idmapped_mnt; then
		[[ "$output" =~ "idmapped" ]]
	elif sysbox_using_shiftfs; then
		[[ "$output" =~ "/var/lib/sysbox/shiftfs/".+"on /lib/modules/${kernel_rel} type shiftfs".+"ro".+"relatime" ]]
	else
		[[ "$output" =~ "on /lib/modules/${kernel_rel}".+"ro".+"relatime" ]]
	fi

	# Verify implicit bind mounts over special dirs use idmapping or chown, but
	# never shiftfs (since an inner Docker or K8s can't mount overlayfs on it).
	if sysbox_using_idmapped_mnt; then
		docker exec "$syscont" sh -c "mount | grep $mnt_dst2 | grep idmapped"
		[ "$status" -eq 0 ]
	elif sysbox_using_shiftfs; then
		docker exec "$syscont" sh -c "mount | grep $mnt_dst2 | grep -v shiftfs"
		[ "$status" -eq 0 ]
	fi

	# Verify explicit bind mounts use idmapping or shiftfs; never chowned.
	if sysbox_using_idmapped_mnt; then
		docker exec "$syscont" sh -c "mount | grep $mnt_dst1 | grep idmapped"
		[ "$status" -eq 0 ]
	elif sysbox_using_shiftfs; then
		docker exec "$syscont" sh -c "mount | grep $mnt_dst1 | grep shiftfs"
		[ "$status" -eq 0 ]
	else
		docker exec "$syscont" sh -c "mount | grep $mnt_dst1 | egrep -v \"shiftfs|idmapped\""
		[ "$status" -eq 0 ]
		mnt_uid=$(__docker exec "$syscont" sh -c "stat -c \"%u\" $mnt_dst1")
		mnt_gid=$(__docker exec "$syscont" sh -c "stat -c \"%g\" $mnt_dst1")
		[ "$file_uid" -eq 65534 ]
		[ "$file_gid" -eq 65534 ]
	fi

	# Verify explicit bind mounts over special dirs use idmapping or chown, never shiftfs
	if sysbox_using_idmapped_mnt; then
		docker exec "$syscont" sh -c "mount | grep $mnt_dst2 | grep idmapped"
		[ "$status" -eq 0 ]
	else
		docker exec "$syscont" sh -c "mount | grep $mnt_dst2 | egrep -v \"shiftfs|idmapped\""
		[ "$status" -eq 0 ]
		mnt_uid=$(__docker exec "$syscont" sh -c "stat -c \"%u\" $mnt_dst2")
		mnt_gid=$(__docker exec "$syscont" sh -c "stat -c \"%g\" $mnt_dst2")
		[ "$file_uid" -eq 0 ]
		[ "$file_gid" -eq 0 ]
	fi

	# cleanup
	docker_stop "$syscont"
	rm -rf $mnt_src1 $mnt_src2
}

# verify sys container has a mount for /lib/modules/<kernel>
@test "kernel lib-module mount" {

  local kernel_rel=$(uname -r)
  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont" sh -c "mount | grep \"/lib/modules/${kernel_rel}\""
  [ "$status" -eq 0 ]

  if sysbox_using_shiftfs_only; then
    [[ "$output" =~ "/var/lib/sysbox/shiftfs/".+"on /lib/modules/${kernel_rel} type shiftfs".+"ro".+"relatime" ]]
  elif sysbox_using_idmapped_mnt; then
    [[ "$output" =~ "idmapped" ]]
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

  if sysbox_using_shiftfs_only; then
    [[ "$output" =~ "/var/lib/sysbox/shiftfs/".+"on /lib/modules/${kernel_rel} type shiftfs".+"ro".+"relatime" ]]
  elif sysbox_using_idmapped_mnt; then
    [[ "$output" =~ "idmapped" ]]
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
      [[ "${distro}" == "rocky" ]] ||
      [[ "${distro}" == "almalinux" ]] ||
      [[ "${distro}" == "redhat" ]]; then

      docker exec "$syscont" sh -c "mount | grep \"/usr/src/kernels/${kernel_rel}\""
      [ "$status" -eq 0 ]

		if sysbox_using_shiftfs_only; then
			[[ "${lines[0]}" =~ "/var/lib/sysbox/shiftfs/".+"on /usr/src/kernels/${kernel_rel} type shiftfs".+"ro".+"relatime" ]]
		elif sysbox_using_idmapped_mnt; then
			[[ "${lines[0]}" =~ "idmapped" ]]
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

	  if sysbox_using_shiftfs_only; then
        [[ "${lines[0]}" =~ "/var/lib/sysbox/shiftfs/".+"on /usr/src/linux-headers-${kernel_rel} type shiftfs".+"ro".+"relatime" ]]
	  elif sysbox_using_idmapped_mnt; then
		  [[ "${lines[0]}" =~ "idmapped" ]]
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
      [[ "${distro}" == "rocky" ]] ||
      [[ "${distro}" == "almalinux" ]] ||
      [[ "${distro}" == "redhat" ]]; then

      docker exec "$syscont" sh -c "mount | grep \"/usr/src/kernels/${kernel_rel}\""
      [ "$status" -eq 0 ]

		if sysbox_using_shiftfs_only; then
			[[ "${lines[0]}" =~ "/var/lib/sysbox/shiftfs".+"on /usr/src/kernels/${kernel_rel} type shiftfs".+"ro".+"relatime" ]]
		elif sysbox_using_idmapped_mnt; then
			[[ "${lines[0]}" =~ "idmapped" ]]
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

	  if sysbox_using_shiftfs_only; then
        [[ "${lines[0]}" =~ "/var/lib/sysbox/shiftfs".+"on /usr/src/linux-headers-${kernel_rel} type shiftfs".+"ro".+"relatime" ]]
	  elif sysbox_using_idmapped_mnt; then
		  [[ "${lines[0]}" =~ "idmapped" ]]
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

@test "chown bind mount over special dir" {

  if sysbox_using_overlayfs_on_idmapped_mnt; then
	  skip "sysbox using id-mapping for mounts over special dirs"
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
  syscont=$(docker_run -v $mnt_src:$mnt_dst ${CTR_IMG_REPO}/alpine-docker-dbg tail -f /dev/null)

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
  # verify uid shifting applied again when the container is restarted
  #
  docker start "$syscont"
  [ "$status" -eq 0 ]

  mnt_src_uid=$(stat -c "%u" $mnt_src)
  mnt_src_gid=$(stat -c "%g" $mnt_src)
  [ "$uid" -eq "$mnt_src_uid" ]
  [ "$gid" -eq "$mnt_src_gid" ]

  docker_stop "$syscont"

  mnt_src_uid=$(stat -c "%u" $mnt_src)
  mnt_src_gid=$(stat -c "%g" $mnt_src)
  [ "$mnt_src_uid" -eq "$orig_mnt_src_uid" ]
  [ "$mnt_src_gid" -eq "$orig_mnt_src_gid" ]

  docker rm "$syscont"
  [ "$status" -eq 0 ]

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

@test "uid-shift bind mount over special dir 2" {

  if sysbox_using_overlayfs_on_idmapped_mnt; then
	  skip "sysbox using id-mapping for mounts over special dirs"
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
  chown 500000:600000 $mnt_src

  orig_mnt_src_uid=$(stat -c "%u" $mnt_src)
  orig_mnt_src_gid=$(stat -c "%g" $mnt_src)

  # Verify chown-based shifting is applied when container starts
  syscont=$(docker_run -v $mnt_src:$mnt_dst ${CTR_IMG_REPO}/alpine-docker-dbg tail -f /dev/null)

  uid=$(docker_root_uid_map $syscont)
  gid=$(docker_root_gid_map $syscont)

  mnt_src_uid=$(stat -c "%u" $mnt_src)
  mnt_src_gid=$(stat -c "%g" $mnt_src)

  [ "$uid" -eq "$mnt_src_uid" ]
  [ "$gid" -eq "$mnt_src_gid" ]

  # Verify chown-based shifting is reverted when container stops
  docker_stop "$syscont"

  mnt_src_uid=$(stat -c "%u" $mnt_src)
  mnt_src_gid=$(stat -c "%g" $mnt_src)
  [ "$mnt_src_uid" -eq "$orig_mnt_src_uid" ]
  [ "$mnt_src_gid" -eq "$orig_mnt_src_gid" ]

  # Change mount ownership
  chown 700000:800000 $mnt_src
  orig_mnt_src_uid=$(stat -c "%u" $mnt_src)
  orig_mnt_src_gid=$(stat -c "%g" $mnt_src)

  docker rm "$syscont"

  # Verify chown-based shifting is applied correctly when container starts
  syscont=$(docker_run -v $mnt_src:$mnt_dst ${CTR_IMG_REPO}/alpine-docker-dbg tail -f /dev/null)

  uid=$(docker_root_uid_map $syscont)
  gid=$(docker_root_gid_map $syscont)

  mnt_src_uid=$(stat -c "%u" $mnt_src)
  mnt_src_gid=$(stat -c "%g" $mnt_src)

  [ "$uid" -eq "$mnt_src_uid" ]
  [ "$gid" -eq "$mnt_src_gid" ]

  docker_stop "$syscont"

  mnt_src_uid=$(stat -c "%u" $mnt_src)
  mnt_src_gid=$(stat -c "%g" $mnt_src)
  [ "$mnt_src_uid" -eq "$orig_mnt_src_uid" ]
  [ "$mnt_src_gid" -eq "$orig_mnt_src_gid" ]

  docker rm "$syscont"
  rm -rf $mnt_src
}

@test "skip chown bind mount over special dir" {

  if sysbox_using_overlayfs_on_idmapped_mnt; then
	  skip "sysbox using id-mapping for mounts over special dirs"
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

@test "mounts with submounts" {

  #
  # Test scenario where sys container is launched with a bind mount of a file
  # that itself is a mount. We've seen this when running Sysbox on K8s clusters,
  # when a K8s secret is mounted on the sysbox container.
  #

  run sh -c 'findmnt | grep -E "shiftfs( |$)"'
  [ "$status" -eq 1 ]

  local basedir="/mnt/scratch"
  rm -rf $basedir/t1
  mkdir $basedir/t1
  echo "f1" > $basedir/t1/f1
  echo "f2" > $basedir/t1/f2
  echo "f3" > $basedir/t1/f3
  echo "f4" > $basedir/t1/f4
  echo "f5" > $basedir/t1/f5
  echo "f6" > $basedir/t1/f6

  rm -rf $basedir/t2
  mkdir $basedir/t2
  echo "t2-f5" > $basedir/t2/f5

  rm -rf $basedir/tmpfs
  mkdir $basedir/tmpfs
  mount -t tmpfs -o size=10M tmpfs $basedir/tmpfs
  echo "f1-tmpfs" >> $basedir/tmpfs/f1-tmpfs

  mount --bind $basedir/tmpfs/f1-tmpfs $basedir/t1/f1
  mount --bind $basedir/t1/f4 $basedir/t1/f3
  mount --bind $basedir/t2/f5 $basedir/t1/f5
  mount --bind /dev/null $basedir/t1/f6

  local syscont=$(docker_run --rm \
									  -v $basedir/t1/f1:/mnt/f1 \
									  -v $basedir/t1/f2:/mnt/f2 \
									  -v $basedir/t1/f3:/mnt/f3 \
									  -v $basedir/t1/f5:/mnt/f5 \
									  -v $basedir/t1/f6:/mnt/f6 \
									  ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont" sh -c "cat /mnt/f1"
  [ "$status" -eq 0 ]
  [[ "$output" == "f1-tmpfs" ]]

  # /mnt/f1 is bind-mounted from $basedir/t1/f1, which is bind-mounted from
  # tmpfs. Since ID-mapped mounts are not yet supported on tmpfs we skip
  # this check.
  if sysbox_using_shiftfs_only; then
	  docker exec "$syscont" sh -c "ls -l /mnt/f1"
	  [ "$status" -eq 0 ]
	  verify_owner "root" "root" "$output"
  fi

  docker exec "$syscont" sh -c "cat /mnt/f2"
  [ "$status" -eq 0 ]
  [[ "$output" == "f2" ]]

  docker exec "$syscont" sh -c "ls -l /mnt/f2"
  [ "$status" -eq 0 ]
  verify_owner "root" "root" "$output"

  docker exec "$syscont" sh -c "cat /mnt/f3"
  [ "$status" -eq 0 ]
  [[ "$output" == "f4" ]]

  docker exec "$syscont" sh -c "ls -l /mnt/f3"
  [ "$status" -eq 0 ]
  verify_owner "root" "root" "$output"

  docker exec "$syscont" sh -c "cat /mnt/f5"
  [ "$status" -eq 0 ]
  [[ "$output" == "t2-f5" ]]

  docker exec "$syscont" sh -c "ls -l /mnt/f5"
  [ "$status" -eq 0 ]
  verify_owner "root" "root" "$output"

  docker exec "$syscont" sh -c "cat /mnt/f6"
  [ "$status" -eq 0 ]
  [[ "$output" == "" ]]

  # f6 is bind mounted from /dev/null, owned by the host's root; thus is shows
  # up as owned by "nobody" in the container.
  docker exec "$syscont" sh -c "ls -l /mnt/f6"
  [ "$status" -eq 0 ]
  verify_owner "nobody" "nobody" "$output"

  docker_stop "$syscont"
  [ "$status" -eq 0 ]

  umount $basedir/t1/f1
  umount $basedir/tmpfs
  umount $basedir/t1/f3
  umount $basedir/t1/f5
  umount $basedir/t1/f6

  rm -rf $basedir/t1
  rm -rf $basedir/t2
  rm -rf $basedir/tmpfs
}

@test "id-map bind mount over special dir" {

  if ! sysbox_using_overlayfs_on_idmapped_mnt; then
	  skip "sysbox using chown for special dirs"
  fi

  local syscont
  local uid
  local gid

  # Verify that sysbox-mgr "shifts" the ownership of a host dir mounted
  # into /var/lib/docker, to match the host uid:gid of the container's
  # root user. The shifting is done via an ID-mapped mount.

  local mnt_src="/mnt/scratch/docker"
  local mnt_dst="/var/lib/docker"

  rm -rf $mnt_src
  mkdir $mnt_src

  orig_mnt_src_uid=$(stat -c "%u" $mnt_src)
  orig_mnt_src_gid=$(stat -c "%g" $mnt_src)

  # Verify ID-mapping is applied when container starts
  syscont=$(docker_run -v $mnt_src:$mnt_dst ${CTR_IMG_REPO}/alpine-docker-dbg tail -f /dev/null)

  docker exec "$syscont" sh -c "mount | grep $mnt_dst"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "idmapped" ]]

  docker exec "$syscont" sh -c "stat -c \"%u\" $mnt_dst"
  [ "$status" -eq 0 ]
  [ "$output" -eq "$orig_mnt_src_uid" ]

  docker exec "$syscont" sh -c "stat -c \"%g\" $mnt_dst"
  [ "$status" -eq 0 ]
  [ "$output" -eq "$orig_mnt_src_gid" ]

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
  # Later we will check if these get ID-mapped correctly when the container is stopped and re-started.

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
  # verify ID-mapping is applied again when the container is restarted
  #

  docker_stop "$syscont"

  docker start "$syscont"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "mount | grep $mnt_dst"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "idmapped" ]]

  docker exec "$syscont" sh -c "stat -c \"%u\" $mnt_dst"
  [ "$status" -eq 0 ]
  [ "$output" -eq "$orig_mnt_src_uid" ]

  docker exec "$syscont" sh -c "stat -c \"%g\" $mnt_dst"
  [ "$status" -eq 0 ]
  [ "$output" -eq "$orig_mnt_src_gid" ]

  docker_stop "$syscont"

  docker rm "$syscont"
  [ "$status" -eq 0 ]

  #
  # Create a new container with the same mount and verify ownership looks good
  #
  syscont=$(docker_run --rm -v $mnt_src:$mnt_dst ${CTR_IMG_REPO}/alpine-docker-dbg tail -f /dev/null)

  docker exec "$syscont" sh -c "stat -c \"%u\" $mnt_dst"
  [ "$status" -eq 0 ]
  [ "$output" -eq "$orig_mnt_src_uid" ]

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

@test "skip ID-mapping over special dir" {

  if ! sysbox_using_overlayfs_on_idmapped_mnt; then
	  skip "sysbox using chown for special dirs"
  fi

  local syscont
  local uid
  local gid

  # verify that sysbox-mgr skips id-mapping of a host dir
  # mounted into /var/lib/docker if the host dir and first-level subdirs
  # match the container's root user uid:gid

  local mnt_src="/mnt/scratch/docker"
  local mnt_dst="/var/lib/docker"

  rm -rf $mnt_src
  mkdir -p $mnt_src/sub1/sub2

  local sysbox_subid=$(grep sysbox /etc/subuid | cut -d":" -f2)

  chown $sysbox_subid:$sysbox_subid $mnt_src $mnt_src/sub1

  sub2_uid=$(( sysbox_subid+1000 ))
  sub2_gid=$(( sysbox_subid+1000 ))

  chown $sub2_uid:$sub2_gid $mnt_src/sub1/sub2

  syscont=$(docker_run --rm -v $mnt_src:$mnt_dst ${CTR_IMG_REPO}/alpine-docker-dbg tail -f /dev/null)

  docker exec "$syscont" sh -c "mount | grep $mnt_dst | grep -v idmapped"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "stat -c \"%u %g\" $mnt_dst"
  [ "$status" -eq 0 ]
  [[ "$output" == "0 0" ]]

  docker exec "$syscont" sh -c "stat -c \"%u %g\" $mnt_dst/sub1"
  [ "$status" -eq 0 ]
  [[ "$output" == "0 0" ]]

  docker exec "$syscont" sh -c "stat -c \"%u %g\" $mnt_dst/sub1/sub2"
  [ "$status" -eq 0 ]
  [[ "$output" == "1000 1000" ]]

  docker_stop "$syscont"

  owner=$(stat -c "%u %g" $mnt_src/sub1)
  [[ "$owner" == "$sysbox_subid $sysbox_subid" ]]

  owner=$(stat -c "%u %g" $mnt_src/sub1/sub2)
  [[ "$owner" == "$sub2_uid $sub2_gid" ]]

  rm -rf $mnt_src
}
