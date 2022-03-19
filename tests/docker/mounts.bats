#!/usr/bin/env bats

#
# Test that docker storage mounts work as expected when using sysbox
#

load ../helpers/run
load ../helpers/docker
load ../helpers/uid-shift
load ../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

@test "docker vol mount" {

  docker volume rm testVol
  docker volume create testVol
  [ "$status" -eq 0 ]

  local syscont=$(docker_run --rm --mount source=testVol,target=/mnt/testVol ${CTR_IMG_REPO}/busybox tail -f /dev/null)

  # verify the mount was done correctly
  docker exec "$syscont" sh -c "mount | grep testVol"
  [ "$status" -eq 0 ]

  # when docker runs in user-ns remap mode, docker volume ownership matches that
  # of the container, so sysbox does not need to mount shiftfs over the volume;
  # otherwise sysbox must mount shiftfs over the volume.
  if docker_userns_remap; then
    [[ "$output" =~ "/dev".+"on /mnt/testVol" ]]
  elif sysbox_using_shiftfs_only; then
    [[ "$output" =~ "/var/lib/sysbox/shiftfs/".+"on /mnt/testVol type shiftfs" ]]
  elif sysbox_using_idmapped_mnt_only; then
    [[ "$output" =~ "idmapped" ]]
  elif sysbox_using_all_uid_shifting; then
    [[ "$output" =~ "idmapped" ]]
  else
	 [[ "$output" =~ "/dev".+"on /mnt/testVol" ]]
  fi

  # verify the container can write and read from the volume
  docker exec "$syscont" sh -c "echo someData > /mnt/testVol/testData"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "cat /mnt/testVol/testData"
  [ "$status" -eq 0 ]
  [[ "$output" == "someData" ]]

  # cleanup
  docker_stop "$syscont"
  docker volume rm testVol
}

@test "docker bind mount" {

  testDir="/mnt/scratch/testVol"
  rm -rf ${testDir}
  mkdir -p ${testDir}

  # Without uid shifting, the bind source must be accessible by
  # the container's user ID.
  if ! sysbox_using_uid_shifting; then
    subid=$(grep sysbox /etc/subuid | cut -d":" -f2)
    chown -R $subid:$subid ${testDir}
  fi

  # start the container
  local syscont=$(docker_run --rm --mount type=bind,source=${testDir},target=/mnt/testVol ${CTR_IMG_REPO}/busybox tail -f /dev/null)

  # verify bind mount was done correctly
  docker exec "$syscont" sh -c "mount | grep testVol"
  [ "$status" -eq 0 ]

  if sysbox_using_shiftfs_only; then
    [[ "$output" =~ "/var/lib/sysbox/shiftfs/".+"on /mnt/testVol type shiftfs" ]]
  elif sysbox_using_idmapped_mnt_only; then
    [[ "$output" =~ "idmapped" ]]
  elif sysbox_using_all_uid_shifting; then
    [[ "$output" =~ "idmapped" ]]
  else
    # overlay because we are running in the test container
    [[ "$output" =~ "overlay on /mnt/testVol type overlay" ]]
  fi

  # verify the container can write and read from the bind mount
  docker exec "$syscont" sh -c "echo someData > /mnt/testVol/testData"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "cat /mnt/testVol/testData"
  [ "$status" -eq 0 ]
  [[ "$output" == "someData" ]]

  # verify the host sees the changes
  run cat "${testDir}/testData"
  [ "$status" -eq 0 ]
  [[ "$output" == "someData" ]]

  # cleanup
  docker_stop "$syscont"
  rm -r ${testDir}
}

@test "docker host socket mount" {

  # launch a sys container with a mount of the host docker socket; this should
  # work fine with idmapped-mounts, but (unfortunately) won't work with shiftfs
  # (see Sysbox issue #404).

  if ! sysbox_using_idmapped_mnt; then
	  skip "Requires Sysbox idmapped mount support"
  fi

  # start the container
  docker_run --rm --name syscont -v /var/run/docker.sock:/var/run/docker.sock ${CTR_IMG_REPO}/alpine-docker-dbg tail -f /dev/null

  # verify the socket has an idmapped mount on it and ownership inside container looks good
  docker exec syscont sh -c "mount | grep 'docker.sock' | grep idmapped"
  [ "$status" -eq 0 ]

  docker exec syscont sh -c "stat -c %u /var/run/docker.sock"
  [ "$status" -eq 0 ]
  [ "$output" -eq 0 ]

  docker exec syscont sh -c "stat -c %g /var/run/docker.sock"
  [ "$status" -eq 0 ]
  [ "$output" -eq 999 ]

  # verify the docker inside the container can access the mounted socket; it
  # should see the container itself.
  docker exec syscont sh -c "docker ps | grep syscont"
  [ "$status" -eq 0 ]

  # cleanup
  docker_stop syscont
}

@test "docker single-file mount" {

  if ! sysbox_using_uid_shifting; then
	  skip "Requires Sysbox uid shifting support"
  fi

  rm -rf /mnt/scratch/testfile
  touch /mnt/scratch/testfile

  # start the container
  local syscont=$(docker_run --rm -v /mnt/scratch/testfile:/mnt/testfile ${CTR_IMG_REPO}/alpine-docker-dbg tail -f /dev/null)

  # verify file was mounted with shiftfs or idmapped-mount, and has proper permissions
  docker exec "$syscont" sh -c "mount | grep testfile"
  [ "$status" -eq 0 ]

  if sysbox_using_shiftfs_only; then
    [[ "$output" =~ "shiftfs" ]]
  elif sysbox_using_idmapped_mnt; then
    [[ "$output" =~ "idmapped" ]]
  fi

  docker exec "$syscont" sh -c "stat -c %u /mnt/testfile"
  [ "$status" -eq 0 ]
  [ "$output" -eq 0 ]

  docker exec "$syscont" sh -c "stat -c %g /mnt/testfile"
  [ "$status" -eq 0 ]
  [ "$output" -eq 0 ]

  # verify the container can read and write the file
  docker exec "$syscont" sh -c "echo data > /mnt/testfile"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "cat /mnt/testfile"
  [ "$status" -eq 0 ]
  [[ "$output" == "data" ]]

  # cleanup
  docker_stop "$syscont"
  rm -rf /mnt/scratch/testfile
}

@test "idmapped mount precedence over shiftfs" {

  if ! sysbox_using_all_uid_shifting; then
	  skip "Requires shiftfs and idmapped mounts."
  fi

  rm -rf /mnt/scratch/testfile
  touch /mnt/scratch/testfile

  # start the container
  local syscont=$(docker_run --rm -v /mnt/scratch/testfile:/mnt/testfile ${CTR_IMG_REPO}/alpine-docker-dbg tail -f /dev/null)

  # verify file was mounted with idmapped-mount (has precedence over shiftfs)
  docker exec "$syscont" sh -c "mount | grep testfile"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "idmapped" ]]

  docker exec "$syscont" sh -c "stat -c %u /mnt/testfile"
  [ "$status" -eq 0 ]
  [ "$output" -eq 0 ]

  docker exec "$syscont" sh -c "stat -c %g /mnt/testfile"
  [ "$status" -eq 0 ]
  [ "$output" -eq 0 ]

  # verify the container can read and write the file
  docker exec "$syscont" sh -c "echo data > /mnt/testfile"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "cat /mnt/testfile"
  [ "$status" -eq 0 ]
  [[ "$output" == "data" ]]

  # cleanup
  docker_stop "$syscont"
  rm -rf /mnt/scratch/testfile
}

@test "docker bind mount skip uid-shift" {

  if ! sysbox_using_uid_shifting; then
	  skip "Requires Sysbox uid shifting support"
  fi

  testDir="/mnt/scratch/testVol"
  rm -rf ${testDir}
  mkdir -p ${testDir}

  # set the volume ownership to match a uid in the sys container uid range; this
  # way, sysbox will skip uid-shifting on the mount.
  subid=$(grep sysbox /etc/subuid | cut -d":" -f2)
  chown -R $((subid+1000)):$((subid+1000)) ${testDir}

  # start the container
  local syscont=$(docker_run --rm --mount type=bind,source=${testDir},target=/mnt/testVol ${CTR_IMG_REPO}/busybox tail -f /dev/null)

  # verify bind mount was done correctly and that uid-shifting was skipped
  docker exec "$syscont" sh -c "mount | grep testVol"
  [ "$status" -eq 0 ]
  echo $output | egrep -qv "idmapped|shiftfs"

  # verify the container can write and read from the bind mount
  docker exec "$syscont" sh -c "echo someData > /mnt/testVol/testData"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "cat /mnt/testVol/testData"
  [ "$status" -eq 0 ]
  [[ "$output" == "someData" ]]

  # verify the host sees the changes
  run cat "${testDir}/testData"
  [ "$status" -eq 0 ]
  [[ "$output" == "someData" ]]

  # cleanup
  docker_stop "$syscont"
  rm -r ${testDir}
}

@test "docker tmpfs mount" {

  # start container with tmpfs mount
  local syscont=$(docker_run --rm --mount type=tmpfs,target=/mnt/testVol ${CTR_IMG_REPO}/busybox tail -f /dev/null)

  # verify the mount was done correctly
  docker exec "$syscont" sh -c "mount | grep testVol"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "tmpfs on /mnt/testVol type tmpfs" ]]

  # verify the container can write and read from the tmpfs mount
  docker exec "$syscont" sh -c "echo someData > /mnt/testVol/testData"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "cat /mnt/testVol/testData"
  [ "$status" -eq 0 ]
  [[ "$output" == "someData" ]]

  # cleanup
  docker_stop "$syscont"
}

@test "vol mount on /var/lib/docker" {

  docker volume rm testVol
  docker volume create testVol
  [ "$status" -eq 0 ]

  local syscont=$(docker_run --rm --mount source=testVol,target=/var/lib/docker ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont" sh -c "findmnt | grep \"\/var\/lib\/docker  \""
  [ "$status" -eq 0 ]

  # deploy an inner container
  docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont

  docker exec "$syscont" sh -c "docker run -d ${CTR_IMG_REPO}/busybox tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker ps --format \"{{.ID}}\""
  [ "$status" -eq 0 ]
  INNER_CONT_NAME="$output"

  docker exec "$syscont" sh -c "docker exec $INNER_CONT_NAME sh -c \"busybox | head -1\""
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ "BusyBox" ]]

  # cleanup
  docker_stop "$syscont"
  docker volume rm testVol
}

@test "bind mount on /var/lib/docker" {

  # testDir will be mounted into the sys container's /var/lib/docker
  testDir="/root/var-lib-docker"
  rm -rf ${testdir}
  mkdir -p ${testDir}

  # Sysbox will modify the ownership of testDir to match the container's uid:gid
  # (because it's mounted over special dir /var/lib/docker). When the container
  # stops, Sysbox will revert the chown. Here we remember the testDir uid:gid so
  # we can later check if Sysbox reverted the ownership.
  orig_tuid=$(stat -c %u "$testDir")
  orig_tgid=$(stat -c %g "$testDir")

  local syscont=$(docker_run --rm --mount type=bind,source=${testDir},target=/var/lib/docker ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont" sh -c "findmnt | grep \"\/var\/lib\/docker  \""
  [ "$status" -eq 0 ]

  line=$(echo $output | tr -s ' ')
  mountSrc=$(echo "$line" | cut -d" " -f 2)
  mountFs=$(echo "$line" | cut -d" " -f 3)

  [[ "$mountSrc" =~ "$testDir" ]]
  [[ "$mountFs" != "shiftfs" ]]
  echo $line | grep -qv "idmapped"

  # Verify sysbox changed the permissions on the mount source.
  uid=$(__docker exec "$syscont" sh -c "cat /proc/self/uid_map | awk '{print \$2}'")
  gid=$(__docker exec "$syscont" sh -c "cat /proc/self/gid_map | awk '{print \$2}'")
  tuid=$(stat -c %u "$testDir")
  tgid=$(stat -c %g "$testDir")
  [ "$uid" -eq "$tuid" ]
  [ "$gid" -eq "$tgid" ]

  # Let's run an inner container to verify the docker inside the sys container
  # can work with /var/lib/docker without problems
  docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont

  docker exec "$syscont" sh -c "docker run -d ${CTR_IMG_REPO}/busybox tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker ps --format \"{{.ID}}\""
  [ "$status" -eq 0 ]
  INNER_CONT_NAME="$output"

  docker exec "$syscont" sh -c "docker exec $INNER_CONT_NAME sh -c \"busybox | head -1\""
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ "BusyBox" ]]

  docker_stop "$syscont"

  # Verify Sysbox revert the ownership on the mount source.
  tuid=$(stat -c %u "$testDir")
  tgid=$(stat -c %g "$testDir")
  [ "$orig_tuid" -eq "$tuid" ]
  [ "$orig_tgid" -eq "$tgid" ]

  # Let's start a new container with the same bind-mount, and verify the mount looks good
  syscont=$(docker_run --rm --mount type=bind,source=${testDir},target=/var/lib/docker ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  uid=$(__docker exec "$syscont" sh -c "cat /proc/self/uid_map | awk '{print \$2}'")
  gid=$(__docker exec "$syscont" sh -c "cat /proc/self/gid_map | awk '{print \$2}'")
  tuid=$(stat -c %u "$testDir")
  tgid=$(stat -c %g "$testDir")
  [ "$uid" -eq "$tuid" ]
  [ "$gid" -eq "$tgid" ]

  docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont

  docker exec "$syscont" sh -c 'docker image ls --format "{{.Repository}}"'
  [ "$status" -eq 0 ]
  images="$output"

  run sh -c "echo \"$images\" | grep busybox"
  [ "$status" -eq 0 ]

  docker_stop "$syscont"

  tuid=$(stat -c %u "$testDir")
  tgid=$(stat -c %g "$testDir")
  [ "$orig_tuid" -eq "$tuid" ]
  [ "$orig_tgid" -eq "$tgid" ]

  # cleanup
  rm -r ${testDir}
}

@test "redundant /var/lib/docker mount" {

  testDir="/root/var-lib-docker"
  rm -rf ${testdir}
  mkdir -p ${testDir}

  local syscont=$(docker_run --rm --mount type=bind,source=${testDir},target=/var/lib/docker ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  # Verify sysbox chowned the testDir at host level
  local uid=$(docker_root_uid_map $syscont)
  local gid=$(docker_root_gid_map $syscont)

  run sh -c "ls -l /root | grep var-lib-docker | awk '{print \$3\":\"\$4}'"
  [ "$status" -eq 0 ]
  [[ "$output" == "$uid:$gid" ]]

  # This docker run is expected to pass but generate a warning (multiple containers can (but should not) share the same /var/lib/docker mount source)
  local syscont_2=$(docker_run --rm --mount type=bind,source=${testDir},target=/var/lib/docker ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  egrep -q "mount source.+should be mounted in one container only" $SYSBOX_MGR_LOG

  # Verify the mount source ownership was changed only once (for the first container only)
  run sh -c "ls -l /root | grep var-lib-docker | awk '{print \$3\":\"\$4}'"
  [ "$status" -eq 0 ]
  [[ "$output" == "$uid:$gid" ]]

  docker_stop "$syscont_2"
  docker_stop "$syscont"

  sleep 2

  syscont=$(docker_run --rm --mount type=bind,source=${testDir},target=/var/lib/docker ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  docker_stop "$syscont"

  rm -r ${testDir}
}

@test "concurrent /var/lib/docker mount" {

  declare -a syscont_name
  declare -a testDir
  declare -a orig_tuid
  declare -a orig_tgid

  num_syscont=4

  subid=$(grep sysbox /etc/subuid | cut -d":" -f2)

  for i in $(seq 0 $(("$num_syscont" - 1))); do
    testDir[$i]="/root/var-lib-docker-$i"
    rm -rf "${testDir[$i]}"
    mkdir -p "${testDir[$i]}"

    orig_tuid[$i]=$(stat -c %u "${testDir[$i]}")
    orig_tgid[$i]=$(stat -c %g "${testDir[$i]}")
  done

  for i in $(seq 0 $(("$num_syscont" - 1))); do
    syscont_name[$i]=$(docker_run --rm --mount type=bind,source="${testDir[$i]}",target=/var/lib/docker ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

    uid=$(__docker exec "${syscont_name[$i]}" sh -c "cat /proc/self/uid_map | awk '{print \$2}'")
    gid=$(__docker exec "${syscont_name[$i]}" sh -c "cat /proc/self/gid_map | awk '{print \$2}'")
    tuid=$(stat -c %u "${testDir[$i]}")
    tgid=$(stat -c %g "${testDir[$i]}")
    [ "$uid" -eq "$tuid" ]
    [ "$gid" -eq "$tgid" ]
  done

  for i in $(seq 0 $(("$num_syscont" - 1))); do
    docker_stop "${syscont_name[$i]}"

    tuid=$(stat -c %u "${testDir[$i]}")
    tgid=$(stat -c %g "${testDir[$i]}")
    [ "${orig_tuid[$i]}" -eq "$tuid" ]
    [ "${orig_tgid[$i]}" -eq "$tgid" ]

    rm -r "${testDir[$i]}"
  done
}

@test "bind mount on /var/lib/kubelet" {

  # testDir will be mounted into the sys container's /var/lib/kubelet
  testDir="/root/var-lib-kubelet"
  rm -rf ${testdir}
  mkdir -p ${testDir}

  orig_tuid=$(stat -c %u "$testDir")
  orig_tgid=$(stat -c %g "$testDir")

  local syscont=$(docker_run --rm --mount type=bind,source=${testDir},target=/var/lib/kubelet ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont" sh -c "findmnt | grep \"\/var\/lib\/kubelet  \""
  [ "$status" -eq 0 ]

  line=$(echo $output | tr -s ' ')
  mountSrc=$(echo "$line" | cut -d" " -f 2)
  mountFs=$(echo "$line" | cut -d" " -f 3)

  [[ "$mountSrc" =~ "$testDir" ]]
  [[ "$mountFs" != "shiftfs" ]]
  echo $line | grep -qv "idmapped"

  uid=$(__docker exec "$syscont" sh -c "cat /proc/self/uid_map | awk '{print \$2}'")
  gid=$(__docker exec "$syscont" sh -c "cat /proc/self/gid_map | awk '{print \$2}'")
  tuid=$(stat -c %u "$testDir")
  tgid=$(stat -c %g "$testDir")
  [ "$uid" -eq "$tuid" ]
  [ "$gid" -eq "$tgid" ]

  # After the container stops, sysbox should revert the ownership on
  # the mount source; verify this.
  docker_stop "$syscont"

  tuid=$(stat -c %u "$testDir")
  tgid=$(stat -c %g "$testDir")
  [ "$orig_tuid" -eq "$tuid" ]
  [ "$orig_tgid" -eq "$tgid" ]

  # cleanup
  rm -r ${testDir}
}

@test "redundant /var/lib/kubelet mount" {

  testDir="/root/var-lib-kubelet"
  rm -rf ${testdir}
  mkdir -p ${testDir}

  local syscont=$(docker_run --rm --mount type=bind,source=${testDir},target=/var/lib/kubelet ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  # This docker run is expected to pass but generate a warning (multiple containers can (but should not) share the same /var/lib/docker mount source)
  local syscont_2=$(docker_run --rm --mount type=bind,source=${testDir},target=/var/lib/kubelet ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  egrep -q "mount source.+should be mounted in one container only" $SYSBOX_MGR_LOG

  docker_stop "$syscont_2"
  docker_stop "$syscont"

  sleep 2

  syscont=$(docker_run --rm --mount type=bind,source=${testDir},target=/var/lib/kubelet ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  docker_stop "$syscont"

  rm -r ${testDir}
}

@test "concurrent /var/lib/kubelet mount" {

  declare -a syscont_name
  declare -a testDir
  declare -a orig_tuid
  declare -a orig_tgid

  num_syscont=4

  subid=$(grep sysbox /etc/subuid | cut -d":" -f2)

  for i in $(seq 0 $(("$num_syscont" - 1))); do
    testDir[$i]="/root/var-lib-kubelet-$i"
    rm -rf "${testDir[$i]}"
    mkdir -p "${testDir[$i]}"

    orig_tuid[$i]=$(stat -c %u "${testDir[$i]}")
    orig_tgid[$i]=$(stat -c %g "${testDir[$i]}")
  done

  for i in $(seq 0 $(("$num_syscont" - 1))); do
    syscont_name[$i]=$(docker_run --rm --mount type=bind,source="${testDir[$i]}",target=/var/lib/kubelet ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

    uid=$(__docker exec "${syscont_name[$i]}" sh -c "cat /proc/self/uid_map | awk '{print \$2}'")
    gid=$(__docker exec "${syscont_name[$i]}" sh -c "cat /proc/self/gid_map | awk '{print \$2}'")
    tuid=$(stat -c %u "${testDir[$i]}")
    tgid=$(stat -c %g "${testDir[$i]}")
    [ "$uid" -eq "$tuid" ]
    [ "$gid" -eq "$tgid" ]
  done

  for i in $(seq 0 $(("$num_syscont" - 1))); do
    docker_stop "${syscont_name[$i]}"

    tuid=$(stat -c %u "${testDir[$i]}")
    tgid=$(stat -c %g "${testDir[$i]}")
    [ "${orig_tuid[$i]}" -eq "$tuid" ]
    [ "${orig_tgid[$i]}" -eq "$tgid" ]

    rm -r "${testDir[$i]}"
  done

}

@test "nested mount sources" {

   rm -rf /mnt/scratch/testdir
   rm -rf /mnt/scratch/testdir/subdir

   docker run --runtime=sysbox-runc --rm \
          -v /mnt/scratch/testdir:/mnt/subdir \
          -v /mnt/scratch/testdir/subdir:/mnt/testdir/subdir \
          -v /mnt/scratch/var-lib-docker-cache:/var/lib/docker \
          ${CTR_IMG_REPO}/alpine-docker-dbg:latest \
          echo hello

   [ "$status" -eq 0 ]

   rm -rf /mnt/scratch/testdir
   rm -rf /mnt/scratch/testdir/subdir

   mkdir -p /mnt/scratch/subdir/var-lib-docker-cache

	# Nested mount sources
   docker run --runtime=sysbox-runc --rm \
          -v /mnt/scratch/subdir:/mnt/scratch/subdir \
          -v /mnt/scratch/subdir/var-lib-docker-cache:/var/lib/docker \
          ${CTR_IMG_REPO}/alpine-docker-dbg:latest \
          echo hello

   [ "$status" -eq 0 ]

	# Nested mount sources (without uid shifting)
   orig_uid=$(stat -c '%U' /mnt/scratch/subdir)
   orig_gid=$(stat -c '%U' /mnt/scratch/subdir)

   subid=$(grep sysbox /etc/subuid | cut -d":" -f2)
   chown $subid:$subid /mnt/scratch/subdir

   docker run --runtime=sysbox-runc --rm \
          -v /mnt/scratch/subdir:/mnt/scratch/subdir \
          -v /mnt/scratch/subdir/var-lib-docker-cache:/var/lib/docker \
          ${CTR_IMG_REPO}/alpine-docker-dbg:latest \
          echo hello

   [ "$status" -eq 0 ]

   rm -rf /mnt/scratch/subdir
}

@test "bind mount above container rootfs" {

	if ! sysbox_using_shiftfs_only; then
		skip "Fails without shiftfs"
	fi

	docker run --runtime=sysbox-runc --rm \
          -v /var/lib:/mnt/var/lib \
          ${CTR_IMG_REPO}/alpine-docker-dbg:latest \
          echo hello

	[ "$status" -eq 0 ]
}
