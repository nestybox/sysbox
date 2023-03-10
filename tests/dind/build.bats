#!/usr/bin/env bats

#
# Test for creating sys containers images with docker images inside
#

load ../helpers/run
load ../helpers/docker
load ../helpers/uid-shift
load ../helpers/sysbox-health
load ../helpers/cgroups
load ../helpers/environment

function teardown() {
  sysbox_log_check
}

@test "build with inner images" {

  if sysbox_using_rootfs_cloning; then
	  skip "docker build with sysbox does not work without shiftfs or kernel 5.19+"
  fi

  # Needs cgroups v1 because the sys container carries docker 19.03 which does not support cgroups v2.
  if host_is_cgroup_v2; then
	  skip "requires host in cgroup v1"
  fi

  # Reconfigure Docker's default runtime to sysbox-runc
  #
  # Note: for some reason this does not work on bats. I worked-around
  # it by configuring the docker daemon in the sysbox test container
  # to use the sysbox-runc as it's default runtime.
  #
  # dockerd_stop
  # cp /etc/docker/daemon.json /etc/docker/daemon.json.bak
  # (cat /etc/docker/daemon.json 2>/dev/null || echo '{}') | jq '. + {"default-runtime": "sysbox-runc"}' > /tmp/tmp.json
  # mv /tmp/tmp.json /etc/docker/daemon.json
  # dockerd_start

  # do a docker build with appropriate dockerfile
  pushd .
  cd tests/dind
  DOCKER_BUILDKIT=0 docker build --no-cache -t sc-with-inner-img:latest .
  [ "$status" -eq 0 ]

  docker image prune -f
  [ "$status" -eq 0 ]
  popd

  # run generated container to confirm that images are embedded in it
  local syscont=$(docker_run --rm sc-with-inner-img:latest tail -f /dev/null)

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

  run sh -c "echo \"$images\" | grep mknod-test"
  [ "$status" -eq 0 ]

  # run an inner container using one of the embedded images
  docker exec "$syscont" sh -c "docker run --rm -d ${CTR_IMG_REPO}/busybox tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker ps --format \"{{.ID}}\""
  [ "$status" -eq 0 ]
  local inner_cont="$output"

  docker exec "$syscont" sh -c "docker exec $inner_cont sh -c \"busybox | head -1\""
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ "BusyBox" ]]

  # run an inner container with the mknod-test image and verify the special FIFO
  # device is present in it.
  docker exec "$syscont" sh -c "docker run --rm -d ${CTR_IMG_REPO}/mknod-test tail -f /dev/null"
  [ "$status" -eq 0 ]

  inner_cont="$output"

  docker exec "$syscont" sh -c "docker exec $inner_cont sh -c \"ls -l /var/log/ulogd.pcap\""
  [ "$status" -eq 0 ]

  # cleanup
  docker_stop "$syscont"
  docker image rm sc-with-inner-img:latest
  docker image prune -f

  # Note: uncomment this once sysbox issue 294 is fixed
  #
  # if [[ $premount == "true" ]]; then
  #   umount /lib/modules/$(uname -r)
  # fi

  # revert dockerd default runtime config
  # dockerd_stop
  # mv /etc/docker/daemon.json.bak /etc/docker/daemon.json
  # dockerd_start
}

@test "commit with inner images" {

  if sysbox_using_rootfs_cloning; then
	  skip "docker commit with sysbox does not work without shiftfs or kernel 5.19+"
  fi

  # Needs cgroups v1 because the sys container carries docker 19.03 which does
  # not support cgroups v2.
  if host_is_cgroup_v2; then
	  skip "requires host in cgroup v1"
  fi

  # Note: we use alpine-docker-dbg:3.11 as it comes with Docker 19.03 and helps
  # us avoid sysbox issue #187 (lchown error when Docker v20+ pulls inner images
  # with special devices)
  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:3.11 tail -f /dev/null)

  docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont

  docker exec "$syscont" sh -c "echo testdata > /root/testfile"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker pull ${CTR_IMG_REPO}/busybox:latest"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker pull ${CTR_IMG_REPO}/alpine:latest"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker pull ${CTR_IMG_REPO}/mknod-test:latest"
  [ "$status" -eq 0 ]

  # commit the sys container image
  docker image rm -f image-commit
  [ "$status" -eq 0 ]
  docker commit "$syscont" image-commit
  [ "$status" -eq 0 ]

  docker_stop "$syscont"
  docker image prune -f

  # verify the committed image has an appropriate size (slightly
  # bigger than the base image since it includes busybox, alpine, and mknod-test)
  local unique_size=$(__docker system df -v --format '{{json .}}' | jq '.Images[] | select(.Repository == "image-commit") | .UniqueSize' | tr -d '"' | grep -Eo '[[:alpha:]]+|[0-9]+')
  local num=$(echo $unique_size | awk '{print $1}')
  local unit=$(echo $unique_size | awk '{print $3}')
  [ "$num" -lt "15" ]
  [ "$unit" == "MB" ]

  # launch a sys container with the committed image
  syscont=$(docker_run --rm image-commit)

  # verify testfile is present
  docker exec "$syscont" sh -c "cat /root/testfile"
  [ "$status" -eq 0 ]
  [[ "$output" == "testdata" ]]

  # make sure to remove docker.pid & containerd.pid before launching docker (it's in the committed image)
  docker exec "$syscont" sh -c "rm -f /var/run/docker.pid && rm -f /run/docker/containerd/containerd.pid"
  [ "$status" -eq 0 ]

  docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont

  # verify images are present
  docker exec "$syscont" sh -c 'docker image ls --format "{{.Repository}}"'
  [ "$status" -eq 0 ]

  images="$output"

  run sh -c "echo \"$images\" | grep busybox"
  [ "$status" -eq 0 ]

  run sh -c "echo \"$images\" | grep alpine"
  [ "$status" -eq 0 ]

  run sh -c "echo \"$images\" | grep mknod-test"
  [ "$status" -eq 0 ]

  # run an inner container using one of the embedded images
  docker exec "$syscont" sh -c "docker run --rm -d ${CTR_IMG_REPO}/busybox tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker ps --format \"{{.ID}}\""
  [ "$status" -eq 0 ]
  local inner_cont="$output"

  docker exec "$syscont" sh -c "docker exec $inner_cont sh -c \"busybox | head -1\""
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ "BusyBox" ]]

  # run an inner container with the mknod-test image and verify the special FIFO
  # device is present in it.
  docker exec "$syscont" sh -c "docker run --rm -d ${CTR_IMG_REPO}/mknod-test tail -f /dev/null"
  [ "$status" -eq 0 ]

  inner_cont="$output"

  docker exec "$syscont" sh -c "docker exec $inner_cont sh -c \"ls -l /var/log/ulogd.pcap\""
  [ "$status" -eq 0 ]

  # cleanup
  docker_stop "$syscont"
  docker image rm image-commit
}

@test "commit with removed inner image" {

  if sysbox_using_rootfs_cloning; then
	  skip "docker commit with sysbox does not work without shiftfs or kernel 5.19+"
  fi

  if [[ $(get_platform) == "arm64" ]]; then
	  skip "syscont-inner-img not supported on arm64."
  fi

  # launch a sys container that comes with inner images baked-in
  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/syscont-inner-img tail -f /dev/null)

  # the syscont-inner-img has stale *.pid files in it; clean them up as otherwise Docker fails to start
  docker exec -d "$syscont" sh -c "rm -f /run/docker/docker.pid && rm -f /run/docker/containerd/*.pid"
  [ "$status" -eq 0 ]

  docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont

  # remove one of the inner images
  docker exec "$syscont" sh -c "docker image rm busybox"
  [ "$status" -eq 0 ]

  # commit the sys container image
  docker image rm -f image-commit
  docker commit "$syscont" image-commit
  [ "$status" -eq 0 ]

  docker_stop "$syscont"
  docker image prune -f

  # launch a sys container with the newly committed image
  syscont=$(docker_run --rm image-commit)

  # make sure to remove docker.pid & containerd.pid before launching docker (it's in the committed image)
  docker exec "$syscont" sh -c "rm -f /var/run/docker.pid && rm -f /run/docker/containerd/containerd.pid"
  [ "$status" -eq 0 ]

  docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont

  # verify removed image is not present
  docker exec "$syscont" sh -c 'docker image ls --format "{{.Repository}}"'
  [ "$status" -eq 0 ]

  images="$output"

  run sh -c "echo \"$images\" | grep -v busybox"
  [ "$status" -eq 0 ]

  run sh -c "echo \"$images\" | grep alpine"
  [ "$status" -eq 0 ]

  # cleanup
  docker_stop "$syscont"
  docker image rm image-commit
  docker image rm ${CTR_IMG_REPO}/syscont-inner-img:latest
}
