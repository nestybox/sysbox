#!/usr/bin/env bats

#
# Integration test for the sysbox-mgr shiftfs manager
#

load ../helpers/run

function setup() {
  if [ -z "$SHIFT_UIDS" ]; then
    skip "needs UID shifting"
  fi
}

@test "shiftfsMgr basic" {

  local kernel_rel=$(uname -r)

  run sh -c 'findmnt | grep shiftfs'
  [ "$status" -eq 1 ]

  SYSCONT_NAME=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)

  # verify things look good inside the sys container

  docker exec "$SYSCONT_NAME" sh -c "findmnt | egrep \"^/\""
  [ "$status" -eq 0 ]
  [[ "$output" =~ "/ ".+"shiftfs rw,relatime" ]]

  docker exec "$SYSCONT_NAME" sh -c "findmnt | grep \"/etc\""
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ "/etc/resolv.conf".+"/var/lib/docker/containers/$SYSCONT_NAME".+"shiftfs rw,relatime" ]]
  [[ "${lines[1]}" =~ "/etc/hostname".+"/var/lib/docker/containers/$SYSCONT_NAME".+"shiftfs rw,relatime" ]]
  [[ "${lines[2]}" =~ "/etc/hosts".+"/var/lib/docker/containers/$SYSCONT_NAME".+"shiftfs rw,relatime" ]]

  docker exec "$SYSCONT_NAME" sh -c "findmnt | grep \"/lib/modules/${kernel_rel}\""
  [ "$status" -eq 0 ]
  [[ "$output" =~ "/lib/modules/${kernel_rel}".+"shiftfs ro,relatime" ]]

  docker exec "$SYSCONT_NAME" sh -c "findmnt | grep \"/usr/src/linux-headers-${kernel_rel}\""
  [ "$status" -eq 0 ]
  [[ "$output" =~ "/usr/src/linux-headers-${kernel_rel}".+"shiftfs ro,relatime" ]]

  # verify things look good on the host
  run sh -c 'findmnt | grep shiftfs | grep "/lib/modules/${kernel_rel}" | awk "{ print \$3\":\"\$4 }"'
  [ "$status" -eq 0 ]
  [[ "$output" =~ "/lib/modules/${kernel_rel}".+"shiftfs" ]]

  run sh -c 'findmnt | grep shiftfs | grep "/usr/src/linux-headers-${kernel_rel}" | awk "{ print \$3\":\"\$4 }"'
  [ "$status" -eq 0 ]
  [[ "$output" =~ "/usr/src/linux-headers-${kernel_rel}".+"shiftfs" ]]

  run sh -c 'findmnt | grep shiftfs | grep "/var/lib/docker/containers" | awk "{ print \$3\":\"\$4 }"'
  [ "$status" -eq 0 ]
  [[ "$output" =~ "/var/lib/docker/containers/$SYSCONT_NAME".+"shiftfs" ]]

  run sh -c 'findmnt | grep shiftfs | grep "/var/lib/docker" | grep -v "containers"'
  [ "$status" -eq 0 ]
  [[ "$output" =~ "/var/lib/docker/".+"shiftfs".+"rw,relatime,mark" ]]

  docker_stop "$SYSCONT_NAME"

  # verify shiftfs mounts for container were removed
  run sh -c 'findmnt | grep shiftfs'
  [ "$status" -eq 1 ]
}

@test "shiftfsMgr multiple syscont" {

  local kernel_rel=$(uname -r)

  run sh -c 'findmnt | grep shiftfs'
  [ "$status" -eq 1 ]

  # num_syscont must be >= 2
  num_syscont=2
  declare -a syscont_name

  for i in $(seq 0 $(("$num_syscont" - 1))); do
    syscont_name[$i]=$(docker_run --rm --hostname "syscont_$i" nestybox/alpine-docker-dbg:latest tail -f /dev/null)
  done

  # verify shiftfs mounts on each look good
  for i in $(seq 0 $(("$num_syscont" - 1))); do
    docker exec "${syscont_name[$i]}" sh -c "findmnt | egrep \"^/\""
    [ "$status" -eq 0 ]
    [[ "$output" =~ "/ ".+"shiftfs rw,relatime" ]]

    docker exec "${syscont_name[$i]}" sh -c "findmnt | grep \"/etc\""
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" =~ "/etc/resolv.conf".+"/var/lib/docker/containers/${syscont_name[$i]}".+"shiftfs rw,relatime" ]]
    [[ "${lines[1]}" =~ "/etc/hostname".+"/var/lib/docker/containers/${syscont_name[$i]}".+"shiftfs rw,relatime" ]]
    [[ "${lines[2]}" =~ "/etc/hosts".+"/var/lib/docker/containers/${syscont_name[$i]}".+"shiftfs rw,relatime" ]]

    docker exec "${syscont_name[$i]}" sh -c "findmnt | grep \"/lib/modules/${kernel_rel}\""
    [ "$status" -eq 0 ]
    [[ "$output" =~ "/lib/modules/${kernel_rel}".+"shiftfs ro,relatime" ]]

    docker exec "${syscont_name[$i]}" sh -c "findmnt | grep \"/usr/src/linux-headers-${kernel_rel}\""
    [ "$status" -eq 0 ]
    [[ "$output" =~ "/usr/src/linux-headers-${kernel_rel}".+"shiftfs ro,relatime" ]]
  done

  # verify mounts on host look good; there should only be one shiftfs mount on lib-modules and kernel-headers
  run sh -c "findmnt | grep shiftfs | grep \"/lib/modules/${kernel_rel}\" | wc -l"
  [ "$status" -eq 0 ] &&  [ "$output" -eq 1 ]

  run sh -c "mount | grep shiftfs | grep \"/usr/src/linux-headers-${kernel_rel}\" | wc -l"
  [ "$status" -eq 0 ] &&  [ "$output" -eq 1 ]

  # and there should be a per-container mount on /var/lib/docker/...
  run sh -c 'findmnt | grep shiftfs | grep "/var/lib/docker/containers" | wc -l'
  [ "$status" -eq 0 ] && [ "$output" -eq "$num_syscont" ]

  run sh -c 'findmnt | grep shiftfs | grep "/var/lib/docker" | grep -v "containers" | wc -l'
  [ "$status" -eq 0 ] && [ "$output" -eq "$num_syscont" ]

  # stop all but the first sys cont and verify mounts on host look good
  for i in $(seq 1 $(("$num_syscont" - 1))); do
    docker_stop "${syscont_name[$i]}"
  done

  run sh -c "findmnt | grep shiftfs | grep \"/lib/modules/${kernel_rel}\""
  [ "$status" -eq 0 ]
  [[ "$output" =~ "/lib/modules/${kernel_rel}".+"shiftfs" ]]

  run sh -c "findmnt | grep shiftfs | grep \"/usr/src/linux-headers-${kernel_rel}\""
  [ "$status" -eq 0 ]
  [[ "$output" =~ "/usr/src/linux-headers-${kernel_rel}".+"shiftfs" ]]

  run sh -c 'findmnt | grep shiftfs | grep "/var/lib/docker/containers" | wc -l'
  [ "$status" -eq 0 ] && [ "$output" -eq 1 ]

  run sh -c 'findmnt | grep shiftfs | grep "/var/lib/docker" | grep -v "containers" | wc -l'
  [ "$status" -eq 0 ] && [ "$output" -eq 1 ]

  # stop last sys cont and verify shiftfs mounts on host are gone
  docker_stop "${syscont_name[0]}"

  run sh -c 'findmnt | grep shiftfs'
  [ "$status" -eq 1 ]
}

@test "shiftfsMgr skip shiftfs on bind-mount" {

  #
  # Test scenario where sysbox skips mounting shiftfs on a bind mount
  # directory that is already marked with shiftfs
  #

  run sh -c 'findmnt | grep shiftfs'
  [ "$status" -eq 1 ]

  # Create a tmp directory to serve as a bind-mount into a sys container
  bind_src=$(mktemp -d "$WORK_DIR/bind_src.XXXXXX")

  # Set a shiftfs mark on the directory
  run mount -t shiftfs -o mark "$bind_src" "$bind_src"
  [ "$status" -eq 0 ]

  # Launch sys container with bind mount
  SYSCONT_NAME=$(docker_run --rm --mount type=bind,source=${bind_src},target=/mnt/target nestybox/alpine-docker-dbg:latest tail -f /dev/null)

  # verify things look good inside the sys container
  docker exec "$SYSCONT_NAME" sh -c 'findmnt | grep shiftfs | grep "/mnt/target" | wc -l'
  [ "$status" -eq 0 ] && [ "$output" -eq 1 ]

  # Check things look good on the host
  run sh -c "findmnt | grep shiftfs | grep $bind_src | wc -l"
  [ "$status" -eq 0 ] && [ "$output" -eq 1 ]

  # stop sys container and verify that shiftfs mount on the bind-mount directory remains
  docker_stop "$SYSCONT_NAME"
  run sh -c "findmnt | grep shiftfs | grep $bind_src | wc -l"
  [ "$status" -eq 0 ] && [ "$output" -eq 1 ]

  # Cleanup
  run sh -c "umount $bind_src"
  [ "$status" -eq 0 ]

  run rmdir "$bind_src"
  [ "$status" -eq 0 ]
}

@test "shiftfsMgr shiftfs file mount" {

  #
  # Test scenario where sys container is launched with a bind mount of a file (not a directory)
  #

  run sh -c 'findmnt | grep shiftfs'
  [ "$status" -eq 1 ]

  bind_src=$(mktemp -d "$WORK_DIR/bind_src.XXXXXX")
  test_file="$bind_src/testFile"
  run touch "$test_file"
  [ "$status" -eq 0 ]

  SYSCONT_NAME=$(docker_run --rm --mount type=bind,source=${test_file},target=/mnt/testFile nestybox/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$SYSCONT_NAME" sh -c 'findmnt | grep shiftfs | grep "/mnt/testFile" | wc -l'
  [ "$status" -eq 0 ] && [ "$output" -eq 1 ]

  run sh -c "findmnt | grep shiftfs | grep $bind_src | wc -l"
  [ "$status" -eq 0 ] && [ "$output" -eq 1 ]

  docker_stop "$SYSCONT_NAME"
  run sh -c 'findmnt | grep shiftfs'
  [ "$status" -eq 1 ]
}

@test "shiftfsMgr shiftfs no-exec on host" {

  bind_src=$(mktemp -d "/work/bind_src.XXXXXX")
  test_file="$bind_src/testFile"

  run touch "$test_file"
  [ "$status" -eq 0 ]

  run chmod +x "$test_file"
  [ "$status" -eq 0 ]

  run "$test_file"
  [ "$status" -eq 0 ]

  # this mount will implicitly set the no-exec attribute on the mountpoint
  run mount -t shiftfs -o mark "$bind_src" "$bind_src"
  [ "$status" -eq 0 ]

  run "$test_file"
  [ "$status" -eq 126 ]
  [[ "$output" == *"Permission denied"* ]]

  # cleanup
  run sh -c "umount $bind_src"
  [ "$status" -eq 0 ]

  run rm -rf "$bind_src"
  [ "$status" -eq 0 ]
}

@test "shiftfsMgr bind-mount no-exec" {

  #
  # Remount a bind-mount as no-exec prior to mounting into sys container.
  # (as recommended for extra security in the Sysbox usage guide).
  #

  # Create a tmp directory to serve as a bind-mount into a sys container
  bind_src=$(mktemp -d "$WORK_DIR/bind_src.XXXXXX")

  # Remount the bind source as no-exec
  run mount --bind "$bind_src" "$bind_src"
  [ "$status" -eq 0 ]

  run mount -o remount,bind,noexec "$bind_src" "$bind_src"
  [ "$status" -eq 0 ]

  # Launch sys container with bind mount
  SYSCONT_NAME=$(docker_run --rm --mount type=bind,source=${bind_src},target=/mnt/target nestybox/alpine-docker-dbg:latest tail -f /dev/null)

  # Verify things look good inside the sys container
  docker exec "$SYSCONT_NAME" sh -c 'findmnt | grep shiftfs | grep "/mnt/target" | wc -l'
  [ "$status" -eq 0 ] && [ "$output" -eq 1 ]

  # Create an exec file on the bind mount dir
  docker exec "$SYSCONT_NAME" sh -c 'touch /mnt/target/testFile && chmod +x /mnt/target/testFile'
  [ "$status" -eq 0 ]

  # Try executing the test file from the host
  run "$bind_src/testFile"
  [ "$status" -eq 126 ]
  [[ "$output" == *"Permission denied"* ]]

  # stop sys container
  docker_stop "$SYSCONT_NAME"
  run sh -c 'findmnt | grep shiftfs'
  [ "$status" -eq 1 ]

  # Try executing the test file from the host and verify it still is no-exec
  run "$bind_src/testFile"
  [ "$status" -eq 126 ]
  [[ "$output" == *"Permission denied"* ]]

  # Cleanup
  run sh -c "umount $bind_src"
  [ "$status" -eq 0 ]

  run rm -rf "$bind_src"
  [ "$status" -eq 0 ]
}
