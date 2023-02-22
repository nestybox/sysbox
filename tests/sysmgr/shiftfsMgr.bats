#!/usr/bin/env bats

#
# Integration test for the sysbox-mgr shiftfs manager
#

load ../helpers/docker
load ../helpers/environment
load ../helpers/fs
load ../helpers/run
load ../helpers/sysbox-health
load ../helpers/uid-shift
load ../helpers/setup

function setup() {
  if ! sysbox_using_shiftfs_only; then
    skip "requires only shiftfs"
  fi

  if docker_userns_remap; then
    skip "docker userns-remap"
  fi
}

function teardown() {
  sysbox_log_check
}

@test "shiftfsMgr basic" {

  local kernel_rel=$(uname -r)
  local kernel_headers_path=$(get_kernel_headers_path)

  run sh -c 'findmnt | grep -E "shiftfs( |$)"'
  [ "$status" -eq 1 ]

  # verify that /var/lib/sysbox/shiftfs has root-only access (for security)
  verify_perm_owner "drwx--x---" "root" "root" $(ls -l /var/lib/sysbox | grep shiftfs)

  SYSCONT_NAME=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  # verify things look good inside the sys container
  docker exec "$SYSCONT_NAME" sh -c "findmnt | egrep \"^/\""
  [ "$status" -eq 0 ]
  [[ "$output" =~ "/ ".+"shiftfs rw,relatime" ]]

  docker exec "$SYSCONT_NAME" sh -c "findmnt | grep \"/etc\""
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ "/etc/resolv.conf".+"/var/lib/sysbox/shiftfs/".+"shiftfs rw,relatime" ]]
  [[ "${lines[1]}" =~ "/etc/hostname".+"/var/lib/sysbox/shiftfs/".+"shiftfs rw,relatime" ]]
  [[ "${lines[2]}" =~ "/etc/hosts".+"/var/lib/sysbox/shiftfs/".+"shiftfs rw,relatime" ]]

  docker exec "$SYSCONT_NAME" sh -c "findmnt | grep \"/lib/modules/${kernel_rel}\""
  [ "$status" -eq 0 ]
  [[ "$output" =~ "/lib/modules/${kernel_rel}".+"/var/lib/sysbox/shiftfs/".+"shiftfs ro,relatime" ]]

  docker exec "$SYSCONT_NAME" sh -c "findmnt | grep \"${kernel_headers_path}\""
  [ "$status" -eq 0 ]
  [[ "$output" =~ "${kernel_headers_path}".+"/var/lib/sysbox/shiftfs/".+"shiftfs ro,relatime" ]]

  # verify things look good on the host
  run sh -c "findmnt | grep shiftfs | grep \"/lib/modules/${kernel_rel}\""
  [ "$status" -eq 0 ]
  [[ "$output" =~ "/var/lib/sysbox/shiftfs/".+"/lib/modules/${kernel_rel}".+"shiftfs" ]]

  run sh -c "findmnt | grep shiftfs | grep \"${kernel_headers_path}\""
  [ "$status" -eq 0 ]
  [[ "$output" =~ "/var/lib/sysbox/shiftfs/".+"${kernel_headers_path}".+"shiftfs" ]]

  run sh -c "findmnt | grep shiftfs | grep \"/var/lib/docker/containers\""
  [ "$status" -eq 0 ]
  [[ "$output" =~ "/var/lib/sysbox/shiftfs/".+"/var/lib/docker/containers/$SYSCONT_NAME".+"shiftfs" ]]

  run sh -c 'findmnt | grep shiftfs | grep "/var/lib/docker" | grep -v "containers"'
  [ "$status" -eq 0 ]
  [[ "$output" =~ "/var/lib/docker/".+"shiftfs".+"rw,relatime,mark" ]]

  docker_stop "$SYSCONT_NAME"

  # verify shiftfs mounts for container were removed
  run sh -c 'findmnt | grep -E "shiftfs( |$)"'
  [ "$status" -eq 1 ]
}

@test "shiftfsMgr multiple syscont" {

  local kernel_rel=$(uname -r)
  local kernel_headers_path=$(get_kernel_headers_path)

  run sh -c 'findmnt | grep -E "shiftfs( |$)"'
  [ "$status" -eq 1 ]

  # num_syscont must be >= 2
  num_syscont=2
  declare -a syscont_name

  for i in $(seq 0 $(("$num_syscont" - 1))); do
    syscont_name[$i]=$(docker_run --rm --hostname "syscont_$i" ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  done

  # verify shiftfs mounts on each look good
  for i in $(seq 0 $(("$num_syscont" - 1))); do
    docker exec "${syscont_name[$i]}" sh -c "findmnt | egrep \"^/\""
    [ "$status" -eq 0 ]
    [[ "$output" =~ "/ ".+"shiftfs rw,relatime" ]]

    docker exec "${syscont_name[$i]}" sh -c "findmnt | grep \"/etc\""
    [ "$status" -eq 0 ]
	 [[ "${lines[0]}" =~ "/etc/resolv.conf".+"/var/lib/sysbox/shiftfs/".+"shiftfs rw,relatime" ]]
	 [[ "${lines[1]}" =~ "/etc/hostname".+"/var/lib/sysbox/shiftfs/".+"shiftfs rw,relatime" ]]
	 [[ "${lines[2]}" =~ "/etc/hosts".+"/var/lib/sysbox/shiftfs/".+"shiftfs rw,relatime" ]]

    docker exec "${syscont_name[$i]}" sh -c "findmnt | grep \"/lib/modules/${kernel_rel}\""
    [ "$status" -eq 0 ]
	 [[ "$output" =~ "/lib/modules/${kernel_rel}".+"/var/lib/sysbox/shiftfs/".+"shiftfs ro,relatime" ]]

    docker exec "${syscont_name[$i]}" sh -c "findmnt | grep \"${kernel_headers_path}\""
    [ "$status" -eq 0 ]
	 [[ "$output" =~ "${kernel_headers_path}".+"/var/lib/sysbox/shiftfs/".+"shiftfs ro,relatime" ]]
  done

  # verify mounts on host look good; there should only be one shiftfs mount on
  # lib-modules and kernel-headers (it's shared among all containers)
  run sh -c "findmnt | grep \"/var/lib/sysbox/shiftfs\" | grep \"/lib/modules/${kernel_rel}\" | wc -l"
  [ "$status" -eq 0 ] &&  [ "$output" -eq 1 ]

  run sh -c "mount | grep \"/var/lib/sysbox/shiftfs\" | grep \"${kernel_headers_path}\" | wc -l"
  [ "$status" -eq 0 ] &&  [ "$output" -eq 1 ]

  # and there should be a per-container shiftfs mount on /var/lib/docker/containers
  run sh -c 'findmnt | grep "/var/lib/sysbox/shiftfs" | grep "/var/lib/docker/containers" | wc -l'
  [ "$status" -eq 0 ] && [ "$output" -eq "$num_syscont" ]

  # and a per-container shiftfs mount on the container's rootfs
  run sh -c 'findmnt | grep shiftfs | grep "/var/lib/docker" | grep -v "containers" | wc -l'
  [ "$status" -eq 0 ] && [ "$output" -eq "$num_syscont" ]

  # stop all but the first sys cont and verify mounts on host look good
  for i in $(seq 1 $(("$num_syscont" - 1))); do
    docker_stop "${syscont_name[$i]}"
  done

  run sh -c "findmnt | grep \"/var/lib/sysbox/shiftfs\" | grep \"/lib/modules/${kernel_rel}\""
  [ "$status" -eq 0 ]
  [[ "$output" =~ "/lib/modules/${kernel_rel}".+"shiftfs" ]]

  run sh -c "findmnt | grep \"/var/lib/sysbox/shiftfs\" | grep \"${kernel_headers_path}\""
  [ "$status" -eq 0 ]
  [[ "$output" =~ "${kernel_headers_path}".+"shiftfs" ]]

  run sh -c 'findmnt | grep "/var/lib/sysbox/shiftfs" | grep "/var/lib/docker/containers" | wc -l'
  [ "$status" -eq 0 ] && [ "$output" -eq 1 ]

  run sh -c 'findmnt | grep shiftfs | grep "/var/lib/docker" | grep -v "containers" | wc -l'
  [ "$status" -eq 0 ] && [ "$output" -eq 1 ]

  # stop last sys cont and verify shiftfs mounts on host are gone
  docker_stop "${syscont_name[0]}"

  run sh -c 'findmnt | grep -E "shiftfs( |$)"'
  [ "$status" -eq 1 ]
}

@test "shiftfsMgr skip shiftfs on bind-mount" {

  #
  # Test scenario where sysbox skips mounting shiftfs on a bind mount
  # directory that is already marked with shiftfs
  #

  run sh -c 'findmnt | grep -E "shiftfs( |$)"'
  [ "$status" -eq 1 ]

  # Create a tmp directory to serve as a bind-mount into a sys container
  bind_src=$(mktemp -d "$WORK_DIR/bind_src.XXXXXX")

  # Set a shiftfs mark on the directory
  run mount -t shiftfs -o mark "$bind_src" "$bind_src"
  [ "$status" -eq 0 ]

  # Launch sys container with bind mount
  SYSCONT_NAME=$(docker_run --rm --mount type=bind,source=${bind_src},target=/mnt/target ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  # verify things look good inside the sys container
  docker exec "$SYSCONT_NAME" sh -c 'findmnt | grep shiftfs | grep "/mnt/target" | wc -l'
  [ "$status" -eq 0 ] && [ "$output" -eq 1 ]

  # Check things look good on the host
  run sh -c "findmnt | grep shiftfs | grep $bind_src | wc -l"
  [ "$status" -eq 0 ] && [ "$output" -eq 1 ]

  # sysbox should not have allocated a shiftfs mount for $bind_src under /var/lib/sysbox/shiftfs
  run sh -c "findmnt | grep \"/var/lib/sysbox/shiftfs\" | grep $bind_src"
  [ "$status" -ne 0 ]

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

  run sh -c 'findmnt | grep -E "shiftfs( |$)"'
  [ "$status" -eq 1 ]

  bind_src=$(mktemp -d "$WORK_DIR/bind_src.XXXXXX")
  test_file="$bind_src/testFile"
  run touch "$test_file"
  [ "$status" -eq 0 ]

  SYSCONT_NAME=$(docker_run --rm --mount type=bind,source=${test_file},target=/mnt/testFile ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$SYSCONT_NAME" sh -c 'findmnt | grep shiftfs | grep "/mnt/testFile" | wc -l'
  [ "$status" -eq 0 ] && [ "$output" -eq 1 ]

  run sh -c "findmnt | grep shiftfs | grep $bind_src | wc -l"
  [ "$status" -eq 0 ] && [ "$output" -eq 1 ]

  docker_stop "$SYSCONT_NAME"
  run sh -c 'findmnt | grep -E "shiftfs( |$)"'
  [ "$status" -eq 1 ]

  run rm -rf "$bind_src"
  [ "$status" -eq 0 ]
}

@test "shiftfsMgr shiftfs no-exec on host" {

  bind_src=$(mktemp -d "$WORK_DIR/bind_src.XXXXXX")
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

  # Create a tmp dir that we will bind-mount into the container
  bind_src=$(mktemp -d "$WORK_DIR/bind_src.XXXXXX")

  # Remount the bind source as no-exec
  run mount --bind "$bind_src" "$bind_src"
  [ "$status" -eq 0 ]

  run mount -o remount,bind,noexec "$bind_src" "$bind_src"
  [ "$status" -eq 0 ]

  # Launch sys container with bind mount
  SYSCONT_NAME=$(docker_run --rm --mount type=bind,source=${bind_src},target=/mnt/target ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  # Verify things look good inside the sys container
  docker exec "$SYSCONT_NAME" sh -c 'findmnt | grep shiftfs | grep "/mnt/target" | wc -l'
  [ "$status" -eq 0 ] && [ "$output" -eq 1 ]

  # Have the container create an exec file on the bind mount dir
  docker exec "$SYSCONT_NAME" sh -c 'touch /mnt/target/testFile && chmod +x /mnt/target/testFile'
  [ "$status" -eq 0 ]

  # Try executing the test file from the host
  run "$bind_src/testFile"
  [ "$status" -eq 126 ]
  [[ "$output" == *"Permission denied"* ]]

  # stop sys container
  docker_stop "$SYSCONT_NAME"
  run sh -c 'findmnt | grep -E "shiftfs( |$)"'
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
