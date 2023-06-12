#!/usr/bin/env bats

#
# Verify the "--disable-inner-image-preload" command line option.
#

load ../helpers/run
load ../helpers/sysbox
load ../helpers/docker
load ../helpers/sysbox-health
load ../helpers/environment
load ../helpers/cgroups

function teardown() {
  sysbox_log_check
}

@test "disable-inner-image-preload: preamble" {
   sysbox_stop
   sysbox_start --disable-inner-image-preload
}

@test "disable-inner-image-preload: can't preload images into sysbox container" {

	# start sys container with docker inside, and have the inner docker pull some images
	local syscont=$(docker_run ${CTR_IMG_REPO}/alpine-docker-dbg:3.11 tail -f /dev/null)

	docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
	[ "$status" -eq 0 ]

	wait_for_inner_dockerd $syscont

	docker exec "$syscont" sh -c "docker pull alpine:latest"
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c "docker pull busybox:latest"
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c "docker image ls | wc -l"
	[ "$status" -eq 0 ]
	[ "$output" -eq 3 ]

	docker_stop "$syscont"

	# verify inner images are not sync'd to rootfs
	rootfs_upper_dir=$(docker_cont_rootfs_upper_dir $syscont)

	[ -z "$(ls -A $rootfs_upper_dir/var/lib/docker)" ]

	# restart the container, verify inner images are still there
	docker start "$syscont"
	[ "$status" -eq 0 ]

	docker exec "$syscont" sh -c "rm -f /var/run/docker.pid && rm -f /run/docker/containerd/containerd.pid"
	[ "$status" -eq 0 ]

	docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
	[ "$status" -eq 0 ]

	wait_for_inner_dockerd $syscont

	docker exec "$syscont" sh -c "docker image ls | wc -l"
	[ "$status" -eq 0 ]
	[ "$output" -eq 3 ]

	docker_stop "$syscont"
	docker rm "$syscont"
}

@test "disable-inner-image-preload: container with preloaded images works" {

  # launch a sys container that comes with inner images baked-in
  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/syscont-inner-img tail -f /dev/null)

  # the syscont-inner-img has stale *.pid files in it; clean them up as otherwise Docker fails to start
  docker exec -d "$syscont" sh -c "rm -f /run/docker/docker.pid && rm -f /run/docker/containerd/*.pid"
  [ "$status" -eq 0 ]

  docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont

  # verify inner images are present
  docker exec "$syscont" sh -c "docker image ls | wc -l"
  [ "$status" -eq 0 ]
  [ "$output" -eq 3 ]

  docker exec "$syscont" sh -c "docker run ${CTR_IMG_REPO}/hello-world | grep \"Hello from Docker!\""
  [ "$status" -eq 0 ]

  docker_stop "$syscont"
}

@test "disable-inner-image-preload: commit with inner images no longer works" {

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

  # commit the sys container image with the inner images (will not capture the
  # inner images since Sysbox was started with "--disable-inner-image-preload")
  docker image rm -f image-commit
  [ "$status" -eq 0 ]

  docker commit "$syscont" image-commit
  [ "$status" -eq 0 ]

  docker_stop "$syscont"
  docker image prune -f

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

  # verify inner images are NOT present
  docker exec "$syscont" sh -c "docker image ls | wc -l"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]

  # cleanup
  docker_stop "$syscont"
  docker image rm image-commit
}

@test "disable-inner-image-preload: post" {
   sysbox_stop
   sysbox_start
}
