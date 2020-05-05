#!/usr/bin/env bats

#
# Verify sys container mounts setup by the sysbox-mgr
#

load ../helpers/run
load ../helpers/sysbox-health

# verify sys container has a mount for /lib/modules/<kernel>
@test "kernel lib-module mount" {

  local kernel_rel=$(uname -r)
  local syscont=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont" sh -c "mount | grep \"/lib/modules/${kernel_rel}\""
  [ "$status" -eq 0 ]

  if [ -n "$SHIFT_UIDS" ]; then
    [[ "$output" =~ "/lib/modules/${kernel_rel} on /lib/modules/${kernel_rel} type shiftfs".+"ro,relatime" ]]
  else
    [[ "$output" =~ "on /lib/modules/${kernel_rel}".+"ro,relatime" ]]
  fi

  docker_stop "$syscont"
}

# verify sys container has a mount for /usr/src/linux-headers-<kernel>
@test "kernel headers mounts" {

  local kernel_rel=$(uname -r)
  local syscont=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont" sh -c "mount | grep \"/usr/src/linux-headers-${kernel_rel}\""
  [ "$status" -eq 0 ]

  if [ -n "$SHIFT_UIDS" ]; then
    [[ "${lines[0]}" =~ "/usr/src/linux-headers-${kernel_rel} on /usr/src/linux-headers-${kernel_rel} type shiftfs".+"ro,relatime" ]]
  else
    [[ "${lines[0]}" =~ "on /usr/src/linux-headers-${kernel_rel}".+"ro,relatime" ]]
  fi

  docker_stop "$syscont"
}
