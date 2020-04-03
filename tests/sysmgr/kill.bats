#!/usr/bin/env bats

#
# Integration test for sysbox-mgr handling of kill signals
#

load ../helpers/run
load ../helpers/docker

load ../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

@test "kill SIGTERM" {

  local syscont0=$(docker_run --rm nestybox/syscont-inner-img:latest tail -f /dev/null)
  local syscont1=$(docker_run --rm nestybox/syscont-inner-img:latest tail -f /dev/null)

  # write some data into the sys container's /var/lib/docker; we will
  # later verify that this data is sync'd to the sys container's
  # rootfs when sysbox is killed.

  docker exec "$syscont0" sh -c "touch /var/lib/docker/testfile"
  [ "$status" -eq 0 ]

  if [ -n "$SB_INSTALLER" ]; then
    systemctl stop sysbox
  else
    # kill sends SIGTERM by default
    kill $(pidof sysbox-fs) && kill $(pidof sysbox-mgr)
    retry_run 5 1 "grep -q Exiting /var/log/sysbox-mgr.log"
  fi

  # verify sysbox-mgr has cleaned up it's state on the host correctly
  if [ -n "$SHIFT_UIDS" ]; then
    run sh -c 'mount | grep -q shiftfs'
    [ "$status" -ne 0 ]
  fi

  run sh -c 'mount | egrep -q "overlay on /var/lib/sysbox/docker"'
  [ "$status" -ne 0 ]

  run sh -c "ls -l /var/lib/sysbox"
  [ "$status" -eq 0 ]
  [[ "$output" == "total 0" ]]

  # verify sysbox-mgr sync'd data back to the sys container's rootfs
  rootfs=$(docker_cont_rootfs $syscont0)
  run sh -c "ls -l $rootfs/var/lib/docker/testfile"
  [ "$status" -eq 0 ]

  # verify sysbox-fs mount is gone
  run sh -c "mount | egrep -q /var/lib/sysboxfs"
  [ "$status" -ne 0 ]

  # stop and remove the containers
  docker_stop "$syscont0"
  docker_stop "$syscont1"

  # restart sysbox
  if [ -n "$SB_INSTALLER" ]; then
    systemctl start sysbox
  else
    bats_bg sysbox
    sleep 2
  fi
}
