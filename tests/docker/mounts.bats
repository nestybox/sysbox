#!/usr/bin/env bats

#
# Test that docker storage mounts work as expected when using sysvisor
#

load ../helpers/run

@test "docker vol mount" {

  docker volume create testVol
  [ "$status" -eq 0 ]

  SYSCONT_NAME=$(docker_run --rm --mount source=testVol,target=/mnt/testVol busybox tail -f /dev/null)

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
  # in order to pass the sysvisor-runc security check.
  if [ -n "$SHIFT_UIDS" ]; then
    testDir="/root/testVol"
  else
    testDir="/testVol"
  fi

  mkdir ${testDir}

  # when not using uid shifting, the bind source must be accessible by the container's user ID.
  if [ -z "$SHIFT_UIDS" ]; then
    chown -R 165536:165536 ${testDir}
  fi

  # start container
  SYSCONT_NAME=$(docker_run --rm --mount type=bind,source=${testDir},target=/mnt/testVol busybox tail -f /dev/null)

  # verify bind mount was done correctly
  docker exec "$SYSCONT_NAME" sh -c "mount | grep testVol"
  [ "$status" -eq 0 ]

  if [ -n "$SHIFT_UIDS" ]; then
    [[ "$output" =~ "${testDir} on /mnt/testVol type nbox_shiftfs" ]]
  else
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

  # verify mount was done correctly

  # stop container

}

@test "docker shared volume mount" {

  # test that a bind mount with root:root + uid shifting can be shared among many containers

}

@test "docker shared bind mount" {

  # test that a bind mount with root:root + uid shifting can be shared among many containers

}

@test "docker vol mount with contents" {

}

@test "docker bind mount with contents" {

}

@test "docker bind mount security check" {

  # test that a bind mount fails when using uid shifting and path has permission other than root

  # (I think this test exists already, probably in the sysvisor-run unit tests)

}
