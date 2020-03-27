#!/usr/bin/env bats

#
# Integration test for the sysbox-mgr docker-store volume manager
#

load ../helpers/run
load ../helpers/docker
load ../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

@test "dsVolMgr no inner img" {

  local syscont=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)

  #
  # verify things look good inside the sys container
  #

  # "/var/lib/docker" should be bind-mounted from a host dir.
  docker exec "$syscont" sh -c "mount | egrep  \".+ on /var/lib/docker type\""
  [ "$status" -eq 0 ]

  # ownership of "/var/lib/docker" should be root:root
  docker exec "$syscont" sh -c "ls -l /var/lib | grep docker | awk '{print \$3\":\"\$4}'"
  [ "$status" -eq 0 ]
  [[ "$output" == "root:root" ]]

  # there should be no img sharing mounts under /var/lib/docker since
  # this container has no inner images
  docker exec "$syscont" sh -c "mount | grep -c  \"overlay on /var/lib/docker/\""
  [ "$status" -eq 1 ]

  #
  # verify things look good on the host
  #

  # there should be a dir with the container's id under /var/lib/sysbox/docker/baseVol
  local syscont_full_id=$(docker_cont_full_id $syscont)

  run ls /var/lib/sysbox/docker/baseVol/$syscont_full_id
  [ "$status" -eq 0 ]

  # and that dir should have ownership matching the uid(gid) assigned to the container's root user
  local uid=$(docker_root_uid_map $syscont)
  local gid=$(docker_root_gid_map $syscont)

  run sh -c "ls -l /var/lib/sysbox/docker/baseVol | grep $syscont_full_id | awk '{print \$3\":\"\$4}'"
  [ "$status" -eq 0 ]
  [[ "$output" == "$uid:$gid" ]]

  # the /var/lib/sysbox/docker/[imgVol|cowVol] dirs should be empty
  # because the container has no inner images.
  run sh -c "ls -l /var/lib/sysbox/docker/imgVol"
  [ "$status" -eq 0 ]
  [[ "$output" == "total 0" ]]

  run sh -c "ls -l /var/lib/sysbox/docker/cowVol"
  [ "$status" -eq 0 ]
  [[ "$output" == "total 0" ]]

  docker_stop "$syscont"
}

@test "dsVolMgr inner img" {

  local syscont=$(docker_run --rm nestybox/syscont-inner-img:latest tail -f /dev/null)

  #
  # Verify things look good inside the sys container
  #

  # "/var/lib/docker" should be bind-mounted from a host dir.
  docker exec "$syscont" sh -c "mount | egrep  \".+ on /var/lib/docker type\""
  [ "$status" -eq 0 ]

  # ownership of "/var/lib/docker" should be root:root
  docker exec "$syscont" sh -c "ls -l /var/lib | grep docker | awk '{print \$3\":\"\$4}'"
  [ "$status" -eq 0 ]
  [[ "$output" == "root:root" ]]

  # the diff directory for inner docker images should be an overlay mount backed by the sysbox copy-on-write vol
  docker exec "$syscont" sh -c "mount | egrep -c \"overlay on /var/lib/docker/.+/diff type overlay .+lowerdir=/var/lib/sysbox/docker/cowVol.+\""
  [ "$status" -eq 0 ]
  local num_inner_img=$output

  # the /var/lib/docker/overlay2 should have the baked-in inner images, the uid(gid) of which should be root:root
  docker exec "$syscont" sh -c "ls /var/lib/docker/overlay2 | grep -v l"
  [ "$status" -eq 0 ]
  local inner_images=( "${lines[@]}" )

  for inner_image in $inner_images; do
    docker exec "$syscont" sh -c "ls -l /var/lib/docker/overlay2/$inner_image | grep diff | awk '{print \$3\":\"\$4}'"
    [ "$status" -eq 0 ]
    [[ "$output" == "root:root" ]]
  done

  #
  # Verify things look good on the host
  #

 # there should be a dir with the container's id under /var/lib/sysbox/docker/baseVol
  local syscont_full_id=$(docker_cont_full_id $syscont)

  run ls /var/lib/sysbox/docker/baseVol/$syscont_full_id
  [ "$status" -eq 0 ]

  # and that dir should have ownership matching the uid(gid) assigned to the container's root user
  local uid=$(docker_root_uid_map $syscont)
  local gid=$(docker_root_gid_map $syscont)

  run sh -c "ls -l /var/lib/sysbox/docker/baseVol | grep $syscont_full_id | awk '{print \$3\":\"\$4}'"
  [ "$status" -eq 0 ]
  [[ "$output" == "$uid:$gid" ]]

  # the /var/lib/sysbox/docker/imgVol dir should be populated correctly
  syscont_img_id=$(docker_cont_image_id $syscont)
  run sh -c "ls /var/lib/sysbox/docker/imgVol/$syscont_img_id"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq "$num_inner_img" ]

  # the /var/lib/sysbox/docker/cowVol dir should be populated correctly
  for inner_image in $inner_images; do
    local path="/var/lib/sysbox/docker/cowVol/$syscont_full_id/$inner_image"

    run sh -c "ls -l $path | grep lower | awk '{print \$3\":\"\$4}'"
    [ "$status" -eq 0 ]
    [[ "$output" == "root:root" ]]

    run sh -c "ls -l $path | grep merged | awk '{print \$3\":\"\$4}'"
    [ "$status" -eq 0 ]
    [[ "$output" == "$uid:$gid" ]]

    run sh -c "ls -l $path | grep upper | awk '{print \$3\":\"\$4}'"
    [ "$status" -eq 0 ]
    [[ "$output" == "$uid:$gid" ]]

    run sh -c "ls -l $path | grep work | awk '{print \$3\":\"\$4}'"
    [ "$status" -eq 0 ]
    [[ "$output" == "root:root" ]]

    run sh -c "mount | egrep -c \"overlay on $path/merged type overlay\""
    [ "$status" -eq 0 ]
  done

  # stop the container (this removes it since we started it with "--rm")
  docker_stop "$syscont"

  # wait for sysbox-mgr to remove container dirs
  sleep 2

  # check the base vol, img vol and cow vol are empty
  run sh -c "ls /var/lib/sysbox/docker/imgVol/$syscont_img_id"
  [ "$status" -ne 0 ]

  run sh -c "ls /var/lib/sysbox/docker/cowVol/$syscont_full_id"
  [ "$status" -ne 0 ]

  run sh -c "ls /var/lib/sysbox/docker/baseVol/$syscont_full_id"
  [ "$status" -ne 0 ]
}

# Verify the sys container docker-store vol persists across container
# start-stop-start events
@test "dsVolMgr persistence" {

  local syscont=$(docker_run nestybox/syscont-inner-img:latest tail -f /dev/null)

  # Check the sys container's /var/lib/docker and store some dummy data inside of it

  docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont

  docker exec "$syscont" sh -c 'docker image ls --format "{{.Repository}}"'
  [ "$status" -eq 0 ]

  images="$output"

  run sh -c "echo \"$images\" | grep busybox"
  [ "$status" -eq 0 ]

  run sh -c "echo \"$images\" | grep alpine"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "echo data > /var/lib/docker/test"
  [ "$status" -eq 0 ]

  # Stop and re-start the sys container

  docker_stop "$syscont"
  [ "$status" -eq 0 ]

  docker start "$syscont"
  [ "$status" -eq 0 ]

  # Restart docker inside the container; must cleanup the prior docker
  # and container pid file as otherwise Docker may fail to start.

  docker exec "$sycont" sh -c "rm -f /var/run/docker.pid"
  docker exec "$syscont" sh -c "rm -f /run/docker/containerd/containerd.pid"
  docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont

  # Re-check the sys container's /var/lib/docker and verify all is good

  docker exec "$syscont" sh -c 'docker image ls --format "{{.Repository}}"'
  [ "$status" -eq 0 ]

  images="$output"

  run sh -c "echo \"$images\" | grep busybox"
  [ "$status" -eq 0 ]

  run sh -c "echo \"$images\" | grep alpine"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "cat /var/lib/docker/test"
  [ "$status" -eq 0 ]
  [[ "$output" == "data" ]]

  # Cleanup

  docker_stop "$syscont"
  [ "$status" -eq 0 ]

  docker rm "$syscont"
  [ "$status" -eq 0 ]
}

@test "dsVolMgr consecutive restart" {

  local syscont=$(docker_run nestybox/syscont-inner-img:latest tail -f /dev/null)

  # start the inner docker, verify all is good, and store some dummy data in the syscont's /var/lib/docker

  docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont

  docker exec "$syscont" sh -c 'docker image ls --format "{{.Repository}}"'
  [ "$status" -eq 0 ]
  images="$output"

  run sh -c "echo \"$images\" | grep busybox"
  [ "$status" -eq 0 ]

  run sh -c "echo \"$images\" | grep alpine"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "echo data > /var/lib/docker/test"
  [ "$status" -eq 0 ]

  # stop the container

  docker_stop "$syscont"
  [ "$status" -eq 0 ]

  # restart it several times, each time checking that all is good

  for i in $(seq 1 4); do

    docker start "$syscont"
    [ "$status" -eq 0 ]

    docker exec "$syscont" sh -c "rm -f /var/run/docker.pid"
    docker exec "$syscont" sh -c "rm -f /run/docker/containerd/containerd.pid"
    docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
    [ "$status" -eq 0 ]

    wait_for_inner_dockerd $syscont

    docker exec "$syscont" sh -c 'docker image ls --format "{{.Repository}}"'
    [ "$status" -eq 0 ]
    images="$output"

    run sh -c "echo \"$images\" | grep busybox"
    [ "$status" -eq 0 ]

    run sh -c "echo \"$images\" | grep alpine"
    [ "$status" -eq 0 ]

    docker exec "$syscont" sh -c "cat /var/lib/docker/test"
    [ "$status" -eq 0 ]
    [[ "$output" == "data" ]]

    docker_stop "$syscont"
    [ "$status" -eq 0 ]
  done

  docker rm "$syscont"
}

@test "dsVolMgr sync-out" {

  local syscont=$(docker_run nestybox/alpine-docker-dbg:latest tail -f /dev/null)
  local rootfs=$(command docker inspect -f '{{.GraphDriver.Data.UpperDir}}' "$syscont")

  docker exec "$syscont" sh -c "touch /var/lib/docker/dummyFile"
  [ "$status" -eq 0 ]

  docker_stop "$syscont"
  [ "$status" -eq 0 ]

  # verify that dummy file was sync'd to the sys container's rootfs
  run ls "$rootfs/var/lib/docker"
  [ "$status" -eq 0 ]
  [[ "$output" == "dummyFile" ]]

  docker start "$syscont"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "rm /var/lib/docker/dummyFile"
  [ "$status" -eq 0 ]

  docker_stop "$syscont"
  [ "$status" -eq 0 ]

  # verify that dummy file removal was sync'd to the sys container's rootfs
  run ls "$rootfs/var/lib/docker"
  [ "$status" -eq 0 ]
  [[ "$output" == "" ]]

  docker_stop "$syscont"
  docker rm "$syscont"
}

@test "dsVolMgr inner image sharing" {
  local num_syscont=4
  declare -a syscont

  for (( i=0; i<$num_syscont; i++ )); do
    syscont[$i]=$(docker_run --rm nestybox/syscont-inner-img:latest tail -f /dev/null)
  done

  # verify all are sharing a single image in the image vol
  run sh -c "ls /var/lib/sysbox/docker/imgVol | wc -l"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]

  # verify each has an independent /var/lib/docker
  for (( i=0; i<$num_syscont; i++ )); do
    docker exec ${syscont[$i]} sh -c "touch /var/lib/docker/testfile-$i"
    [ "$status" -eq 0 ]
  done

  for (( i=0; i<$num_syscont; i++ )); do
    docker exec ${syscont[$i]} sh -c "ls /var/lib/docker/testfile-$i"
    [ "$status" -eq 0 ]

    j=$(( $i + 1 ))
    docker exec ${syscont[$i]} sh -c "ls /var/lib/docker/testfile-$j"
    [ "$status" -ne 0 ]
  done

  # Stop all containers (removes them because of "--rm")
  for (( i=0; i<$num_syscont; i++ )); do
    docker_stop ${syscont[$i]}
  done

  # wait for sysbox-mgr to remove container dirs
  sleep 2

  # verify image volume is gone
  run sh -c "ls /var/lib/sysbox/docker/imgVol | wc -l"
  [ "$status" -eq 0 ]
  [ "$output" -eq 0 ]
}

@test "dsVolMgr inner image removal" {
  local num_syscont=2
  local inner_images

  declare -a syscont

  # deploy a number of sys containers with "baked-in" inner-images
  for (( i=0; i<$num_syscont; i++ )); do
    syscont[$i]=$(docker_run --rm nestybox/syscont-inner-img:latest tail -f /dev/null)
  done

  # verify sys container inner images are present
  for (( i=0; i<$num_syscont; i++ )); do
    docker exec -d "${syscont[$i]}" sh -c "dockerd > /var/log/dockerd.log 2>&1"
    [ "$status" -eq 0 ]

    wait_for_inner_dockerd ${syscont[$i]}

    docker exec "${syscont[$i]}" sh -c 'docker image ls --format "{{.Repository}}"'
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -ne 0 ]

    if [ "$i" -eq 0 ]; then
      inner_images=( "${lines[@]}" )
    fi
  done

  # remove inner images in the first sys container
  for inner_image in ${inner_images[@]}; do
    docker exec "${syscont[0]}" sh -c "docker image rm $inner_image"
    [ "$status" -eq 0 ]
  done

  # verify removal worked
  docker exec "${syscont[0]}" sh -c 'docker image ls --format "{{.Repository}}"'
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 0 ]

  # verify other containers are unaffected by removal
  for (( i=1; i<$num_syscont; i++ )); do
    docker exec "${syscont[$i]}" sh -c 'docker image ls --format "{{.Repository}}"'
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -ne 0 ]
  done

  # in the first sys container, re-pull one of the removed images
  docker exec "${syscont[0]}" sh -c 'docker pull alpine'
  [ "$status" -eq 0 ]

  docker exec "${syscont[0]}" sh -c 'docker image ls --format "{{.Repository}}"'
  [ "$status" -eq 0 ]
  [[ "$output" == "alpine" ]]

  # cleanup
  for (( i=0; i<$num_syscont; i++ )); do
   docker_stop "${syscont[$i]}"
  done
}
