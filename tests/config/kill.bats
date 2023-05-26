#!/usr/bin/env bats

#
# Integration test for sysbox-mgr handling of kill signals
#

load ../helpers/run
load ../helpers/docker
load ../helpers/uid-shift
load ../helpers/sysbox
load ../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

@test "kill SIGTERM" {

  local syscont0=$(docker_run ${CTR_IMG_REPO}/syscont-inner-img:latest tail -f /dev/null)
  local syscont1=$(docker_run ${CTR_IMG_REPO}/syscont-inner-img:latest tail -f /dev/null)

  # write some data into the sys container's /var/lib/docker; we will
  # later verify that this data is sync'd to the sys container's
  # rootfs when sysbox is killed.

  docker exec "$syscont0" sh -c "touch /var/lib/docker/testfile"
  [ "$status" -eq 0 ]

  sysbox_stop

  # verify sysbox-mgr has cleaned up it's state on the host correctly
  run sh -c 'mount | grep "/var/lib/sysbox"'
  [ "$status" -ne 0 ]

  run sh -c "ls /var/lib/sysbox"
  [ "$status" -ne 0 ]

  # verify sysbox-mgr sync'd data back to the sys container's rootfs; this does
  # not work when the rootfs is cloned under "/var/lib/sysbox", as stopping
  # sysbox causes the contents of that directory to be removed.
  if ! sysbox_using_rootfs_cloning; then
	  rootfs=$(docker_cont_rootfs_upper_dir $syscont0)
	  run sh -c "ls -l $rootfs/var/lib/docker/testfile"
	  [ "$status" -eq 0 ]
  fi

  # verify sysbox-fs mount is gone
  run sh -c "mount | egrep -q /var/lib/sysboxfs"
  [ "$status" -ne 0 ]

  run sh -c "ls /var/lib/sysboxfs"
  [ "$status" -ne 0 ]

  # stop and remove the containers
  docker_stop "$syscont0"
  docker_stop "$syscont1"
  docker rm "$syscont0"
  docker rm "$syscont1"

  sysbox_start

  run sh -c "ls /var/lib/sysbox"
  [ "$status" -eq 0 ]

  run sh -c "ls /var/lib/sysboxfs"
  [ "$status" -eq 0 ]

  # create a new container and verify all is well
  syscont0=$(docker_run --rm ${CTR_IMG_REPO}/syscont-inner-img:latest tail -f /dev/null)

  docker exec "$syscont0" sh -c "touch /var/lib/docker/testfile"
  [ "$status" -eq 0 ]

  docker_stop "$syscont0"
}
