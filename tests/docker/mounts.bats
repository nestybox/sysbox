#!/usr/bin/env bats

#
# Test that docker storage mounts work as expected when using sysbox
#

load ../helpers/run

function wait_for_nested_dockerd {
  retry_run 10 1 eval "__docker exec $SYSCONT_NAME docker ps"
}

@test "docker vol mount" {

  docker volume create testVol
  [ "$status" -eq 0 ]

  SYSCONT_NAME=$(docker_run --rm --mount source=testVol,target=/mnt/testVol busybox tail -f /dev/null)

  # verify the mount was done correctly
  docker exec "$SYSCONT_NAME" sh -c "mount | grep testVol"
  [ "$status" -eq 0 ]

  if [ -n "$SHIFT_UIDS" ]; then
    [[ "$output" =~ "/var/lib/docker/volumes/testVol/_data on /mnt/testVol type nbox_shiftfs" ]]
  else
    [[ "$output" =~ "/dev".+"on /mnt/testVol" ]]
  fi

  # verify the container can write and read from the volume
  docker exec "$SYSCONT_NAME" sh -c "echo someData > /mnt/testVol/testData"
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "cat /mnt/testVol/testData"
  [ "$status" -eq 0 ]
  [[ "$output" == "someData" ]]

  # cleanup
  docker_stop "$SYSCONT_NAME"
  docker volume rm testVol
}

@test "docker bind mount" {

  # when using uid shifting, the bind source must be accessible by root on the host only
  # in order to pass the sysbox-runc security check.
  if [ -n "$SHIFT_UIDS" ]; then
    testDir="/root/testVol"
  else
    testDir="/testVol"
  fi

  mkdir ${testDir}

  # without docker userns-remap, the bind source must be accessible by
  # the container's user ID.
  if [ -z "$SHIFT_UIDS" ]; then
    chown -R 165536:165536 ${testDir}
  fi

  # start the container
  SYSCONT_NAME=$(docker_run --rm --mount type=bind,source=${testDir},target=/mnt/testVol busybox tail -f /dev/null)

  # verify bind mount was done correctly
  docker exec "$SYSCONT_NAME" sh -c "mount | grep testVol"
  [ "$status" -eq 0 ]

  if [ -n "$SHIFT_UIDS" ]; then
    [[ "$output" =~ "${testDir} on /mnt/testVol type nbox_shiftfs" ]]
  else
    # overlay because we are running in the test container
    [[ "$output" =~ "overlay on /mnt/testVol type overlay" ]]
  fi

  # verify the container can write and read from the bind mount
  docker exec "$SYSCONT_NAME" sh -c "echo someData > /mnt/testVol/testData"
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "cat /mnt/testVol/testData"
  [ "$status" -eq 0 ]
  [[ "$output" == "someData" ]]

  # verify the host sees the changes
  run cat "${testDir}/testData"
  [ "$status" -eq 0 ]
  [[ "$output" == "someData" ]]

  # cleanup
  docker_stop "$SYSCONT_NAME"
  rm -r ${testDir}
}

@test "docker tmpfs mount" {

  # start container with tmpfs mount
  SYSCONT_NAME=$(docker_run --rm --mount type=tmpfs,target=/mnt/testVol busybox tail -f /dev/null)

  # verify the mount was done correctly
  docker exec "$SYSCONT_NAME" sh -c "mount | grep testVol"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "tmpfs on /mnt/testVol type tmpfs" ]]

  # verify the container can write and read from the tmpfs mount
  docker exec "$SYSCONT_NAME" sh -c "echo someData > /mnt/testVol/testData"
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "cat /mnt/testVol/testData"
  [ "$status" -eq 0 ]
  [[ "$output" == "someData" ]]

  # cleanup
  docker_stop "$SYSCONT_NAME"
}

@test "docker bind mount security check" {

  testDir="/testVol"
  mkdir ${testDir}

  if [ -n "$SHIFT_UIDS" ]; then
    # verify that a bind mount fails when using uid shifting and the source path is accessible by non-root
    docker run --runtime=sysbox-runc -d --rm --mount type=bind,source=${testDir},target=/mnt/testVol busybox tail -f /dev/null
    [ "$status" -eq 125 ]
    [[ "$output" =~ "shiftfs mountpoint security check failed" ]]
  else
    # verify that a bind mount passes without uid shifting if the source path is accessible by non-root
    SYSCONT_NAME=$(docker_run --rm --mount type=bind,source=${testDir},target=/mnt/testVol busybox tail -f /dev/null)
    docker_stop "$SYSCONT_NAME"
  fi

  rmdir ${testDir}
}

@test "docker bind mount on var-lib-docker" {

  # verify that sysbox ignores user bind-mounts on the sys container's
  # /var/lib/docker, as those are managed by sysbox-mgr

  testDir="/root/var-lib-docker"
  mkdir ${testDir}

  if [ -z "$SHIFT_UIDS" ]; then
    chown -R 165536:165536 ${testDir}
  fi

  SYSCONT_NAME=$(docker_run --rm --mount type=bind,source=${testDir},target=/var/lib/docker nestybox/ubuntu-disco-docker-dbg:latest tail -f /dev/null)

  docker exec "$SYSCONT_NAME" sh -c "findmnt | grep \"\/var\/lib\/docker  \""
  [ "$status" -eq 0 ]

  line=$(echo $output | tr -s ' ')

  mountDest=$(echo "$line" | cut -d" " -f 1)
  mountSrc=$(echo "$line" | cut -d" " -f 2)
  mountFs=$(echo "$line" | cut -d" " -f 3)

  if [ -n "$SHIFT_UIDS" ]; then
    [[ "$mountSrc" =~ "sysbox/docker" ]]
    [[ "$mountFs" != "nbox_shiftfs" ]]
  else
    [[ "$mountSrc" =~ "sysbox/docker" ]]
  fi

  # Let's run an inner container to verify the docker inside the sys container
  # can work with /var/lib/docker without problems

  docker exec "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd-log 2>&1 &"
  [ "$status" -eq 0 ]

  wait_for_nested_dockerd

  docker exec "$SYSCONT_NAME" sh -c "docker run --rm -d busybox tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "docker ps --format \"{{.ID}}\""
  [ "$status" -eq 0 ]
  INNER_CONT_NAME="$output"

  docker exec "$SYSCONT_NAME" sh -c "docker exec $INNER_CONT_NAME sh -c \"busybox | head -1\""
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ "BusyBox" ]]

  # cleanup
  docker_stop "$SYSCONT_NAME"
  rm -r ${testDir}
}
