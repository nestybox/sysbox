#!/usr/bin/env bats

#
# Tests that verify seccomp notify mechanism used for syscall trapping
#

load ../helpers/run
load ../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

# verify that sysbox-fs releases the seccomp notify fd when a sys container exits
@test "sysbox-fs releases notify fd" {

  local sysfs_pid=$(pidof sysbox-fs)

  pre=$(lsof -p $sysfs_pid | grep "seccomp notify" | wc -l)

  local syscont_name=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  docker_stop "$syscont_name"

  post=$(lsof -p $sysfs_pid | grep "seccomp notify" | wc -l)

  [ $pre -eq $post ]
}

# verify that sysbox-fs releases the seccomp notify fd when a process that entered the sys container via 'exec' exits
@test "sysbox-fs releases notify fd exec" {

  local sysfs_pid=$(pidof sysbox-fs)

  pre=$(lsof -p $sysfs_pid | grep "seccomp notify" | wc -l)

  local syscont_name=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  docker exec "$syscont_name" echo
  docker_stop "$syscont_name"

  post=$(lsof -p $sysfs_pid | grep "seccomp notify" | wc -l)

  [ $pre -eq $post ]
}
