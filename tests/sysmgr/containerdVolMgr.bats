#!/usr/bin/env bats

#
# Integration test for the sysbox-mgr containerd volume manager
#

load ../helpers/run
load ../helpers/docker
load ../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

@test "containerdVolMgr basic" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  #
  # verify things look good inside the sys container
  #

  # "/var/lib/containerd/io.containerd.snapshotter.v1.overlayfs" should be mounted to "/var/lib/sysbox/containerd/<syscont-name>"; note
  # that in the privileged test container the "/var/lib/sysbox" is itself a mount-point,
  # so it won't show up in findmnt; thus we just grep for "containerd/<syscont-name>"
  docker exec "$syscont" sh -c "findmnt | grep \"/var/lib/containerd/io.containerd.snapshotter.v1.overlayfs\" | grep \"containerd/$syscont\""
  [ "$status" -eq 0 ]

  # ownership of "/var/lib/containerd/io.containerd.snapshotter.v1.overlayfs" should be root:root
  docker exec "$syscont" sh -c "stat /var/lib/containerd/io.containerd.snapshotter.v1.overlayfs | grep Uid"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "Access: (0700/drwx------)  Uid: (    0/    root)   Gid: (    0/    root)" ]]

  #
  # verify things look good on the host
  #

  # there should be a dir with the container's name under /var/lib/sysbox/containerd
  run sh -c "ls /var/lib/sysbox/containerd | grep $syscont"
  [ "$status" -eq 0 ]

  # and that dir should have ownership matching the container's assigned uid (unless overlayfs on ID-mapping works)
  if sysbox_using_overlayfs_on_idmapped_mnt; then
	  local syscont_uid=$(docker_root_uid_map $syscont)

	  run sh -c "stat /var/lib/sysbox/containerd/\"$syscont\"* | grep Uid | grep \"$syscont_uid\""
	  [ "$status" -eq 0 ]
  fi

  docker_stop "$syscont"
}

@test "containerdVolMgr persistence" {

  # Verify the sys container containerd vol persists across container
  # start-stop-start events

  local syscont=$(docker_run ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont" sh -c "echo data > /var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/test"
  [ "$status" -eq 0 ]

  docker_stop "$syscont"
  [ "$status" -eq 0 ]

  docker start "$syscont"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "cat /var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/test"
  [ "$status" -eq 0 ]
  [[ "$output" == "data" ]]

  docker_stop "$syscont"
  [ "$status" -eq 0 ]

  docker rm "$syscont"
  [ "$status" -eq 0 ]
}

@test "containerdVolMgr non-persistence" {

  # Verify the sys container containerd vol is removed when a
  # container is removed

  local syscont=$(docker_run ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  # short ID -> full ID
  run sh -c "docker inspect \"$syscont\" | jq '.[0] | .Id' | sed 's/\"//g'"
  [ "$status" -eq 0 ]
  sc_id="$output"

  docker exec "$syscont" sh -c "echo data > /var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/test"
  [ "$status" -eq 0 ]

  run cat "/var/lib/sysbox/containerd/$sc_id/test"
  [ "$status" -eq 0 ]
  [[ "$output" == "data" ]]

  docker_stop "$syscont"
  [ "$status" -eq 0 ]

  run cat "/var/lib/sysbox/containerd/$sc_id/test"
  [ "$status" -eq 0 ]

  docker rm "$syscont"

  # wait for sysbox to detect the container removal
  sleep 0.5

  run cat "/var/lib/sysbox/containerd/$sc_id/test"
  [ "$status" -eq 1 ]

  run cat "/var/lib/sysbox/containerd/$sc_id"
  [ "$status" -eq 1 ]
}

@test "containerdVolMgr consecutive restart" {

  local syscont=$(docker_run ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont" sh -c "echo data > /var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/test"
  [ "$status" -eq 0 ]

  docker_stop "$syscont"
  [ "$status" -eq 0 ]

  for i in $(seq 1 4); do
    docker start "$syscont"
    [ "$status" -eq 0 ]

    docker exec "$syscont" sh -c "cat /var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/test"
    [ "$status" -eq 0 ]
    [[ "$output" == "data" ]]

    docker_stop "$syscont"
    [ "$status" -eq 0 ]
  done

  docker rm "$syscont"
}

@test "containerdVolMgr sync-out" {

  local syscont=$(docker_run ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)
  local rootfs=$(command docker inspect -f '{{.GraphDriver.Data.UpperDir}}' "$syscont")

  docker exec "$syscont" sh -c "touch /var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/dummyFile"
  [ "$status" -eq 0 ]

  docker_stop "$syscont"
  [ "$status" -eq 0 ]

  # verify that dummy file was sync'd to the sys container's rootfs
  run ls "$rootfs/var/lib/containerd/io.containerd.snapshotter.v1.overlayfs"
  [ "$status" -eq 0 ]
  [[ "$output" == "dummyFile" ]]

  docker start "$syscont"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "rm /var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/dummyFile"
  [ "$status" -eq 0 ]

  docker_stop "$syscont"
  [ "$status" -eq 0 ]

  # verify that dummy file removal was sync'd to the sys container's rootfs
  run ls "$rootfs/var/lib/containerd/io.containerd.snapshotter.v1.overlayfs"
  [ "$status" -eq 0 ]
  [[ "$output" == "" ]]

  docker_stop "$syscont"
  docker rm "$syscont"
}

#@test "containerdVolMgr sync-in" {
  #
  # TODO: verify containerdVolMgr sync-in by creating a sys container image with contents in /var/lib/containerd
  # and checking that the contents are copied to the /var/lib/sysbox/containerd/<syscont-name> and
  # that they have the correct ownership. There is a volMgr unit test that verifies this already,
  # but an integration test would be good too.
  #
#}
