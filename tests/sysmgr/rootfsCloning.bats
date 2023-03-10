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

function setup() {
	if ! sysbox_using_rootfs_cloning && ! docker_userns_remap; then
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
  stat "/var/lib/sysbox/rootfs/$syscont/overlay2"
  stat "/var/lib/sysbox/rootfs/$syscont/overlay2/merged"
  stat "/var/lib/sysbox/rootfs/$syscont/overlay2/diff"
  stat "/var/lib/sysbox/rootfs/$syscont/overlay2/work"

  # verify sysbox-mgr setup the rootfs clone correctly
  run sh -c "mount | grep \"overlay2/merged type overlay\" | wc -l"
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]

  # verify the rootfs clone is bind mounted over the orig rootfs; it's the
  # original overlayfs mount plus the rootfs clone stacked on top of it, plus a
  # redundant bind-to-self mount (see sysbox-mgr rootfs cloner for an
  # explanation of why). Thus a total of 3 stacked mounts.
  run sh -c "mount | grep $orig_rootfs | wc -l"
  [ "$status" -eq 0 ]
  [ "$output" -eq 3 ]

  # verify sysbox-mgr chowned the cloned rootfs
  run stat -c %u "/var/lib/sysbox/rootfs/$syscont/overlay2/merged"
  [ "$status" -eq 0 ]
  [ "$output" -eq "$uid" ]

  run stat -c %g "/var/lib/sysbox/rootfs/$syscont/overlay2/merged"
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
  run stat -c %u "/var/lib/sysbox/rootfs/$syscont/overlay2/merged"
  [ "$status" -eq 0 ]
  [ "$output" -eq 0 ]

  run stat -c %g "/var/lib/sysbox/rootfs/$syscont/overlay2/merged"
  [ "$status" -eq 0 ]
  [ "$output" -eq 0 ]

  # verify rootfs cloned mounts remain

  # there should one less mount over the orig rootfs as Docker removes when the
  # container stops.
  run sh -c "mount | grep $orig_rootfs | wc -l"
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]

  # there should be one less mount over the overlay2/merged dir as it's bound
  # to the orig Docker rootfs
  run sh -c "mount | grep \"overlay2/merged type overlay\" | wc -l"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]

  # restart container
  docker start "$syscont"

  # verify sysbox-mgr chowned the cloned rootfs
  run stat -c %u "/var/lib/sysbox/rootfs/$syscont/overlay2/merged"
  [ "$status" -eq 0 ]
  [ "$output" -eq "$uid" ]

  run stat -c %g "/var/lib/sysbox/rootfs/$syscont/overlay2/merged"
  [ "$status" -eq 0 ]
  [ "$output" -eq "$gid" ]

  # stop & remove container
  docker_stop "$syscont"
  docker rm "$syscont"

  sleep 2

  # verify sysbox-mgr torn down the mounts
  run sh -c "mount | grep \"overlay2/merged type overlay\""
  [ "$status" -ne 0 ]

  run sh -c "mount | grep \"top/merged type overlay\""
  [ "$status" -ne 0 ]

  run sh -c "mount | grep $orig_rootfs"
  [ "$status" -ne 0 ]

  # verify sysbox-mgr deleted the clone
  run stat "/var/lib/sysbox/rootfs/$syscont/"
  [ "$status" -ne 0 ]
}

@test "rootfs-clone no inode leak" {
	# Verify rootfs cloning does not result in inode leakage (see
	# https://github.com/nestybox/sysbox/issues/570).

	docker pull alpine
	[ "$status" -eq 0 ]

	local inode_pre=$(sh -c "df -i / | tail -n 1 | awk '{print \$3}'")
	docker run --runtime=sysbox-runc --rm alpine pwd
	[ "$status" -eq 0 ]

	# Allow sometime for the container inodes to be returned back to the kernel
	sleep 2

	local inode_post=$(sh -c "df -i / | tail -n 1 | awk '{print \$3}'")
	local usage=$(( $inode_post-$inode_pre ))

	# We expect the inode usage not to increase after the container is created
	# then destroyed, but other processes in the host may be consuming inodes at
	# this time, so we have to fudge it a bit.
	[ $usage -lt 10 ]
}
