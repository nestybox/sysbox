#!/usr/bin/env bats

#
# Verify sysbox-mgr command line arguments
#

load ../helpers/run
load ../helpers/docker
load ../helpers/uid-shift
load ../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

function sysbox_mgr_stopped() {
   if ! pgrep sysbox-mgr; then
      echo true
   else
      echo false
   fi
}

@test "--data-root" {

   local new_data_root="/mnt/scratch/sysbox-mgr"
   rm -rf $new_data_root

   # Stop the sysbox-mgr
   sysbox_mgr_stop

   # Verify the sysbox data root is gone
   run sh -c "ls /var/lib/sysbox"
   [ "$status" -ne 0 ]

   # Create a new data root for it
   mkdir -p $new_data_root

   # Start it with the new data root
   sysbox_mgr_start --data-root $new_data_root

   # Verify the prior sysbox data root is now replaced by the new one
   run sh -c "ls /var/lib/sysbox"
   [ "$status" -ne 0 ]

   run sh -c "ls ${new_data_root}"
   [ "$status" -eq 0 ]

   # Launch an sys container and verify all is good
   local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

   docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
   [ "$status" -eq 0 ]

   wait_for_inner_dockerd $syscont

   docker exec "$syscont" sh -c "docker run -d --rm ${CTR_IMG_REPO}/alpine tail -f /dev/null"
   [ "$status" -eq 0 ]

   # Verify the new data root is in use
   run ls $new_data_root
   [ "$status" -eq 0 ]
   [[ "$output" =~ "containerd".+"docker".+"kubelet" ]]

   docker_stop "$syscont"

   # Stop the sysbox-mgr
   sysbox_mgr_stop

	# Verify the new data-root is gone
	run sh -c "ls ${new_data_root}"
	[ "$status" -ne 0 ]

   # Re-start it with it's default data-root
   sysbox_mgr_start

	# Verify the prior sysbox data root is now replaced by the new one
	run sh -c "ls ${new_data_root}"
	[ "$status" -ne 0 ]

	run sh -c "ls /var/lib/sysbox"
	[ "$status" -eq 0 ]
}

@test "--disable-rootfs-cloning" {

  sysbox_mgr_stop
  sysbox_mgr_start --disable-shiftfs --disable-rootfs-cloning

  local syscont=$(docker_run ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  syscont=$(docker_cont_full_id $syscont)
  rootfs=$(docker_cont_rootfs $syscont)
  uid=$(docker_root_uid_map $syscont)
  gid=$(docker_root_uid_map $syscont)

  # verify no rootfs cloning was done
  run stat "/var/lib/sysbox/rootfs/$syscont/"
  [ "$status" -ne 0 ]

  # verify sysbox-mgr chowned the rootfs to match the container's assigned
  # user-ns uid:gid
  run stat -c %u "$rootfs"
  [ "$status" -eq 0 ]
  [ "$output" -eq "$uid" ]

  run stat -c %g "$rootfs"
  [ "$status" -eq 0 ]
  [ "$output" -eq "$uid" ]

  # verify things look good inside the container
  docker exec "$syscont" sh -c "stat -c %u /"
  [ "$status" -eq 0 ]
  [ "$output" -eq 0 ]

  docker exec "$syscont" sh -c "stat -c %g /"
  [ "$status" -eq 0 ]
  [ "$output" -eq 0 ]

  # stop container
  docker_stop "$syscont"

  # restart container
  docker start "$syscont"

  # verify things look good inside the container
  docker exec "$syscont" sh -c "stat -c %u /"
  [ "$status" -eq 0 ]
  [ "$output" -eq 0 ]

  docker exec "$syscont" sh -c "stat -c %g /"
  [ "$status" -eq 0 ]
  [ "$output" -eq 0 ]

  docker_stop "$syscont"
  docker rm "$syscont"

  sysbox_start
}
