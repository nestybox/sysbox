#!/usr/bin/env bats

#
# Verify sysbox-mgr command line arguments
#

load ../helpers/run
load ../helpers/docker
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

@test "data-root" {

   local new_data_root="/mnt/scratch/sysbox-mgr"
   rm -rf $new_data_root

   # Stop the sysbox-mgr
   sysbox_mgr_stop

   # Create a new data root for it
   mkdir -p $new_data_root

   # Start it with the new data root
   sysbox_mgr_start --data-root $new_data_root

   # Launch an sys container and verify all is good
   local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

   docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
   [ "$status" -eq 0 ]

   wait_for_inner_dockerd $syscont

   docker exec "$syscont" sh -c "docker run -d --rm alpine tail -f /dev/null"
   [ "$status" -eq 0 ]

   # Verify the new data root is in use
   run ls $new_data_root
   [ "$status" -eq 0 ]
   [[ "$output" =~ "containerd".+"docker".+"kubelet" ]]

   docker_stop "$syscont"

   # Stop the sysbox-mgr
   sysbox_mgr_stop

   # Re-start it with it's default data-root
   sysbox_mgr_start

   # Cleanup
   rm -rf $new_data_root
}
