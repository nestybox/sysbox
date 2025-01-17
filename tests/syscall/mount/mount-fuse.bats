#!/usr/bin/env bats

#
# Verify mount and umount of FUSE-backed filesystem inside a Sysbox container
#

load ../../helpers/run
load ../../helpers/docker
load ../../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

@test "FUSE mount & unmount" {
  local syscont=$(docker_run --rm --device /dev/fuse ${CTR_IMG_REPO}/sysbox-issue-854 tail -f /dev/null)

  # create a fuse-backed mount at fuse-mountpoint using sample_fuse.py, and tell
  # it to "passthrough" /etc to the fuse mountpoint.
  docker exec ${syscont} sh -c "cd /tmp && mkdir ./fuse-mountpoint && ./sample_fuse.py /etc ./fuse-mountpoint"
  [ "$status" -eq 0 ]

  # /etc/hostname should how show up under the fuse mountpoint
  docker exec ${syscont} sh -c "ls -l /tmp/fuse-mountpoint | grep hostname"
  [ "$status" -eq 0 ]

  # unmount the fuse mountpoint
  docker exec ${syscont} sh -c "cd /tmp && umount-path ./fuse-mountpoint"
  [ "$status" -eq 0 ]

  # /etc/hostname should no longer show up under the fuse mountpoint
  docker exec ${syscont} sh -c "ls -l /tmp/fuse-mountpoint | grep hostname"
  [ "$status" -ne 0 ]

  docker_stop ${syscont}
}
