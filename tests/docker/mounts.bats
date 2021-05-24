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
  # of the container, so sysbox does not need to mount shiftfs over the volume.
  if [ -n "$SHIFT_UIDS" ]; then
    [[ "$output" =~ "/var/lib/docker/volumes/testVol/_data on /mnt/testVol type shiftfs" ]]
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

  testDir="/testVol"
  mkdir -p ${testDir}

  # without uid shifting, the bind source must be accessible by
  # the container's user ID.
  if ! host_supports_uid_shifting; then
    subid=$(grep sysbox /etc/subuid | cut -d":" -f2)
    chown -R $subid:$subid ${testDir}
  fi

  # start the container
  local syscont=$(docker_run --rm --mount type=bind,source=${testDir},target=/mnt/testVol ${CTR_IMG_REPO}/busybox tail -f /dev/null)

  # verify bind mount was done correctly
  docker exec "$syscont" sh -c "mount | grep testVol"
  [ "$status" -eq 0 ]

  if host_supports_uid_shifting; then
    [[ "$output" =~ "${testDir} on /mnt/testVol type shiftfs" ]]
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

  # This docker run is expected to pass but generate a warning (multiple containers can (but should not) share the same /var/lib/docker mount source)
  local syscont_2=$(docker_run --rm --mount type=bind,source=${testDir},target=/var/lib/docker ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  egrep -q "mount source.+should be mounted in one container only" $SYSBOX_MGR_LOG

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

	docker run --runtime=sysbox-runc --rm \
          -v /mnt/a:/mnt/a \
          -v /mnt/scratch/a:/mnt/scratch/a \
          -v /mnt/scratch/var-lib-docker-cache:/var/lib/docker \
          ${CTR_IMG_REPO}/alpine-docker-dbg:latest \
          echo hello

	[ "$status" -eq 0 ]

	rmdir /mnt/a
	rmdir /mnt/scratch/a

	# If the mount is on a special dir, and the source of that mount is a child
	# dir of another bind-mount source that requires uid-shifting, sysbox-runc
	# will disallow it. Verify this.
	if host_supports_uid_shifting; then
		docker run --runtime=sysbox-runc --rm \
				 -v /mnt/scratch:/mnt/scratch \
				 -v /mnt/scratch/var-lib-docker-cache:/var/lib/docker \
				 ${CTR_IMG_REPO}/alpine-docker-dbg:latest \
				 echo hello
		[ "$status" -ne 0 ]
	fi

	# If the mount is on a special dir, and the source of that mount is a child
	# dir of another bind-mount source that **does not** require uid-shifting,
	# sysbox-runc will allow it. Verify this.
	orig_uid=$(stat -c '%U' /mnt/scratch)
	orig_gid=$(stat -c '%U' /mnt/scratch)

	subid=$(grep sysbox /etc/subuid | cut -d":" -f2)
   chown $subid:$subid /mnt/scratch

	docker run --runtime=sysbox-runc --rm \
          -v /mnt/scratch:/mnt/scratch \
          -v /mnt/scratch/var-lib-docker-cache:/var/lib/docker \
          ${CTR_IMG_REPO}/alpine-docker-dbg:latest \
          echo hello

	[ "$status" -eq 0 ]

   chown $orig_uid:$orig_gid /mnt/scratch
}

@test "shiftfs blacklist" {

	if ! host_supports_uid_shifting; then
		skip "needs uid shifting"
	fi

	# this list must match the sysbox-run shiftfs blacklist
	declare -a blacklist=("/bin" "/sbin" "/usr/bin" "/usr/sbin" "/usr/local/bin" "/usr/loca/sbin" "/dev" "/run" "/var/run")
	local syscont

	for bind_src in ${blacklist[@]}; do

		run stat $blacklist
		if [ "$output" -ne 0 ]; then
			continue
		fi

		syscont=$(docker_run --rm --mount type=bind,source=$blacklist,target=/mnt/$blacklist ${CTR_IMG_REPO}/busybox tail -f /dev/null)

		# verify that shiftfs is not mounted on the source or destination of the mount
		run sh -c "mount | grep \"shiftfs\" | grep \"$blacklist\""
		[ "$status" -eq 1 ]

		docker exec "$syscont" sh -c "mount | grep \"shiftfs\" | grep \"/mnt/$blacklist\""
		[ "$status" -eq 1 ]

		docker_stop "$syscont"
	done
}
