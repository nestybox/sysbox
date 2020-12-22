#!/usr/bin/env bats

#
# Verify trapping & emulation on "chown", "fchown", and "fchownat"
#

load ../helpers/run
load ../helpers/docker
load ../helpers/fs
load ../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

function verify_proc_owner() {
   owner=$1
   group=$2
   docker exec "$syscont" sh -c "ls -l / | grep proc"
   [ "$status" -eq 0 ]
   verify_perm_owner "dr-xr-xr-x" "${owner}" "${group}" "${output}"
}

function verify_sys_owner() {
   owner=$1
   group=$2
   docker exec "$syscont" sh -c "ls -l / | grep sys"
   [ "$status" -eq 0 ]
   verify_perm_owner "dr-xr-xr-x" "${owner}" "${group}" "${output}"
}

function verify_proc_chown() {

  # chown /proc (absolute path)
  docker exec "$syscont" sh -c "chown daemon:daemon /proc"
  [ "$status" -eq 0 ]
  verify_proc_owner daemon daemon

  docker exec "$syscont" sh -c "chown root:root /proc"
  [ "$status" -eq 0 ]
  verify_proc_owner root root

  # chown /proc (relative path)
  docker exec "$syscont" sh -c "cd /root && chown daemon:daemon ../proc"
  [ "$status" -eq 0 ]
  verify_proc_owner daemon daemon

  docker exec "$syscont" sh -c "cd /root && chown root:root ../proc"
  [ "$status" -eq 0 ]
  verify_proc_owner root root
}

function verify_sys_chown {
   owner=$1
   group=$2

  # verify chown /sys is ignored (absolute path)
  docker exec "$syscont" sh -c "chown root:root /sys"
  [ "$status" -eq 0 ]
  verify_sys_owner $owner $group

  # verify chown /sys is ignored (relative path)
  docker exec "$syscont" sh -c "cd /root && chown root:root ../sys"
  [ "$status" -eq 0 ]
  verify_sys_owner $owner $group
}

@test "chown /proc" {
   local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
   verify_proc_owner root root
   verify_proc_chown
   docker_stop "$syscont"
}

@test "chown /sys" {
   local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
   verify_sys_owner nobody nobody
   verify_sys_chown nobody nobody
   docker_stop "$syscont"
}


@test "fchownat /proc" {
   # Note: in Ubuntu, chown uses the fchownat syscall
   local syscont=$(docker_run --rm ubuntu tail -f /dev/null)
   verify_proc_owner root root
   verify_proc_chown
   docker_stop "$syscont"
}

@test "fchownat /sys" {
   # Note: in Ubuntu, chown(1) uses the fchownat syscall
   local syscont=$(docker_run --rm ubuntu tail -f /dev/null)
   verify_sys_owner nobody nogroup
   verify_sys_chown nobody nogroup
   docker_stop "$syscont"
}

@test "chown other" {
  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont" sh -c "mkdir /test"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "ls -l / | grep test"
  [ "$status" -eq 0 ]
  verify_perm_owner "drwxr-xr-x" "root" "root" "${output}"

  docker exec "$syscont" sh -c "chown daemon:daemon /test"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "ls -l / | grep test"
  [ "$status" -eq 0 ]
  verify_perm_owner "drwxr-xr-x" "daemon" "daemon" "${output}"

  docker_stop "$syscont"
}

@test "chown inner container" {
   local syscont=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu-focal-systemd-docker)
   wait_for_inner_dockerd "$syscont"

   docker exec "$syscont" sh -c "docker run -d --rm alpine tail -f /dev/null"
   [ "$status" -eq 0 ]

   docker exec "$syscont" sh -c "docker ps --format \"{{.ID}}\""
   [ "$status" -eq 0 ]
   local inner_cont="$output"

   docker exec "$syscont" sh -c "docker exec $inner_cont sh -c \"ls -l / | grep proc\""
   [ "$status" -eq 0 ]
   verify_perm_owner "dr-xr-xr-x" "root" "root" "${output}"

   docker exec "$syscont" sh -c "docker exec $inner_cont sh -c \"ls -l / | grep sys\""
   [ "$status" -eq 0 ]
   verify_perm_owner "dr-xr-xr-x" "nobody" "nobody" "${output}"

   docker exec "$syscont" sh -c "docker exec $inner_cont sh -c \"chown root:root /proc\""
   [ "$status" -eq 0 ]

   # This chown inside the inner container will be trapped and ignored by sysbox
   docker exec "$syscont" sh -c "docker exec $inner_cont sh -c \"chown root:root /sys\""
   [ "$status" -eq 0 ]

   docker exec "$syscont" sh -c "docker exec $inner_cont sh -c \"ls -l / | grep proc\""
   [ "$status" -eq 0 ]
   verify_perm_owner "dr-xr-xr-x" "root" "root" "${output}"

   docker exec "$syscont" sh -c "docker exec $inner_cont sh -c \"ls -l / | grep sys\""
   [ "$status" -eq 0 ]
   verify_perm_owner "dr-xr-xr-x" "nobody" "nobody" "${output}"

   docker_stop "$syscont"
}

@test "fchownat inner container" {
   local syscont=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu-focal-systemd-docker)
   wait_for_inner_dockerd "$syscont"

   # Note: in Ubuntu, chown(1) uses the fchownat syscall
   docker exec "$syscont" sh -c "docker run -d --rm ubuntu tail -f /dev/null"
   [ "$status" -eq 0 ]

   docker exec "$syscont" sh -c "docker ps --format \"{{.ID}}\""
   [ "$status" -eq 0 ]
   local inner_cont="$output"

   docker exec "$syscont" sh -c "docker exec $inner_cont sh -c \"ls -l / | grep proc\""
   [ "$status" -eq 0 ]
   verify_perm_owner "dr-xr-xr-x" "root" "root" "${output}"

   docker exec "$syscont" sh -c "docker exec $inner_cont sh -c \"ls -l / | grep sys\""
   [ "$status" -eq 0 ]
   verify_perm_owner "dr-xr-xr-x" "nobody" "nogroup" "${output}"

   docker exec "$syscont" sh -c "docker exec $inner_cont sh -c \"chown root:root /proc\""
   [ "$status" -eq 0 ]

   # This chown inside the inner container will be trapped and ignored by sysbox
   docker exec "$syscont" sh -c "docker exec $inner_cont sh -c \"chown root:root /sys\""
   [ "$status" -eq 0 ]

   docker exec "$syscont" sh -c "docker exec $inner_cont sh -c \"ls -l / | grep proc\""
   [ "$status" -eq 0 ]
   verify_perm_owner "dr-xr-xr-x" "root" "root" "${output}"

   docker exec "$syscont" sh -c "docker exec $inner_cont sh -c \"ls -l / | grep sys\""
   [ "$status" -eq 0 ]
   verify_perm_owner "dr-xr-xr-x" "nobody" "nogroup" "${output}"

   docker_stop "$syscont"
}
