#!/usr/bin/env bats

#
# Integration test for sysbox-mgr rootfs cloning feature (used in scenarios
# where Sysbox needs to chown the rootfs and shiftfs is not present, such
# as in Fedora/RHEL hosts).
#

load ../helpers/run
load ../helpers/docker
load ../helpers/uid-shift
load ../helpers/sysbox-health

function sysbox_rootfs_cloning_disabled() {
  ps -fu root | grep "$(pidof sysbox-mgr)" | grep -q "disable-rootfs-cloning"
}

function setup() {
  if sysbox_using_shiftfs || docker_userns_remap || sysbox_rootfs_cloning_disabled; then
	  skip "rootfs cloning not active"
  fi
}

function teardown() {
  sysbox_log_check
}

@test "rootfs-clone basic" {

  # verify no rootfs clones exist yet (want to start clean)
  run sh -c "ls -l /var/lib/sysbox/rootfs"
  [ "$status" -ne 0 ] || [[ "$output" == "total 0" ]]

  local syscont=$(docker_run ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  syscont=$(docker_cont_full_id $syscont)
  orig_rootfs=$(docker_cont_rootfs $syscont)
  uid=$(docker_root_uid_map $syscont)
  gid=$(docker_root_uid_map $syscont)

  # verify sysbox-mgr cloned the rootfs
  stat "/var/lib/sysbox/rootfs/$syscont/"
  stat "/var/lib/sysbox/rootfs/$syscont/top"
  stat "/var/lib/sysbox/rootfs/$syscont/top/merged"
  stat "/var/lib/sysbox/rootfs/$syscont/top/diff"
  stat "/var/lib/sysbox/rootfs/$syscont/top/work"
  stat "/var/lib/sysbox/rootfs/$syscont/bottom"
  stat "/var/lib/sysbox/rootfs/$syscont/bottom/merged"
  stat "/var/lib/sysbox/rootfs/$syscont/bottom/diff"
  stat "/var/lib/sysbox/rootfs/$syscont/bottom/work"

  # verify sysbox-mgr setup the rootfs clone "bottom mount" correctly
  run sh -c "mount | grep \"bottom/merged type overlay\" | wc -l"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]

  # verify sysbox-mgr setup the rootfs clone "top mount" correctly; it has a
  # bind-to-self on top, so we should see two such mounts.
  run sh -c "mount | grep \"top/merged type overlay\" | wc -l"
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]

  # verify the rootfs clone is bind mounted over the orig rootfs; it's the
  # original overlayfs mount plus the rootfs top mount stacked on top of it.
  # since the latter is 2 mounts, we get a total of 3 stacked mounts.
  run sh -c "mount | grep $orig_rootfs | wc -l"
  [ "$status" -eq 0 ]
  [ "$output" -eq 3 ]

  # verify sysbox-mgr chowned the cloned rootfs
  run stat -c %u "/var/lib/sysbox/rootfs/$syscont/bottom/merged"
  [ "$status" -eq 0 ]
  [ "$output" -eq "$uid" ]

  run stat -c %g "/var/lib/sysbox/rootfs/$syscont/bottom/merged"
  [ "$status" -eq 0 ]
  [ "$output" -eq "$gid" ]

  # verify things look good inside the container
  docker exec "$syscont" sh -c "stat -c %u /"
  [ "$status" -eq 0 ]
  [ "$output" -eq 0 ]

  docker exec "$syscont" sh -c "stat -c %g /"
  [ "$status" -eq 0 ]
  [ "$output" -eq 0 ]

  # stop container
  docker_stop "$syscont"

  # verify sysbox-mgr revert-chowned the cloned rootfs
  run stat -c %u "/var/lib/sysbox/rootfs/$syscont/bottom/merged"
  [ "$status" -eq 0 ]
  [ "$output" -eq 0 ]

  run stat -c %g "/var/lib/sysbox/rootfs/$syscont/bottom/merged"
  [ "$status" -eq 0 ]
  [ "$output" -eq 0 ]

  # verify rootfs cloned mounts remain

  # there should one less mount over the orig rootfs as Docker removes when the
  # container stops.
  run sh -c "mount | grep $orig_rootfs | wc -l"
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]

  # there should be one less mount over the top/merged dir as it's bound
  # to the orig Docker rootfs
  run sh -c "mount | grep \"top/merged type overlay\" | wc -l"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]

  run sh -c "mount | grep \"bottom/merged type overlay\" | wc -l"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]

  # restart container
  docker start "$syscont"

  # verify sysbox-mgr chowned the cloned rootfs
  run stat -c %u "/var/lib/sysbox/rootfs/$syscont/bottom/merged"
  [ "$status" -eq 0 ]
  [ "$output" -eq "$uid" ]

  run stat -c %g "/var/lib/sysbox/rootfs/$syscont/bottom/merged"
  [ "$status" -eq 0 ]
  [ "$output" -eq "$gid" ]

  # stop & remove container
  docker_stop "$syscont"
  docker rm "$syscont"

  sleep 2

  # verify sysbox-mgr torn down the mounts
  run sh -c "mount | grep \"bottom/merged type overlay\""
  [ "$status" -ne 0 ]

  run sh -c "mount | grep \"top/merged type overlay\""
  [ "$status" -ne 0 ]

  run sh -c "mount | grep $orig_rootfs"
  [ "$status" -ne 0 ]

  # verify sysbox-mgr deleted the clone
  run stat "/var/lib/sysbox/rootfs/$syscont/"
  [ "$status" -ne 0 ]
}
