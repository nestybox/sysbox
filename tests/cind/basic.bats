#!/usr/bin/env bats

#
# Basic tests running containerd inside a system container
#

load ../helpers/run
load ../helpers/docker
load ../helpers/containerd
load ../helpers/sysbox-health
load ../helpers/uid-shift

function teardown() {
  sysbox_log_check
}

@test "cind basic" {

  syscont=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu-focal-docker-dbg:latest tail -f /dev/null)

  docker exec -d "$syscont" sh -c "containerd > /var/log/containerd.log --log-level=debug 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_containerd $syscont

  docker exec "$syscont" sh -c "ctr image pull ${CTR_IMG_REPO}/hello-world:latest"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "ctr image ls -q"
  [ "$status" -eq 0 ]
  [[ "$output" == "${CTR_IMG_REPO}/hello-world:latest" ]]

  docker exec "$syscont" sh -c "ctr container create ${CTR_IMG_REPO}/hello-world:latest demo"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "ctr container ls -q"
  [ "$status" -eq 0 ]
  [[ "$output" == "demo" ]]

  docker exec "$syscont" sh -c "ctr container delete demo"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "ctr image remove ${CTR_IMG_REPO}/hello-world:latest"
  [ "$status" -eq 0 ]
  [[ "$output" == "${CTR_IMG_REPO}/hello-world:latest" ]]

  docker_stop "$syscont"
}

@test "commit with inner images" {

  if sysbox_using_rootfs_cloning; then
	  skip "docker commit with sysbox does not work without shiftfs or kernel 5.19+"
  fi

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu-jammy-docker:latest tail -f /dev/null)

  docker exec -d "$syscont" sh -c "containerd > /var/log/containerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_containerd $syscont

  docker exec "$syscont" sh -c "echo testdata > /root/testfile"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "ctr image pull ${CTR_IMG_REPO}/busybox:latest"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "ctr image pull ${CTR_IMG_REPO}/alpine:latest"
  [ "$status" -eq 0 ]

  # commit the sys container image
  docker image rm -f image-commit
  docker commit "$syscont" image-commit
  [ "$status" -eq 0 ]

  docker_stop "$syscont"
  docker image prune -f

  # verify the committed image has an appropriate size (slightly bigger than the
  # base image since it includes inner containerd busybox & alpine images).
  #
  # note: this check only works when Docker is using the Docker image store, as
  # otherwise docker system df does not report the image's unique size.
  if docker_containerd_image_store; then
		local unique_size=$(__docker system df -v --format '{{json .}}' | jq '.Images[] | select(.Repository == "image-commit") | .UniqueSize' | tr -d '"' | grep -Eo '[[:alpha:]]+|[0-9]+')
		local num=$(echo $unique_size | awk '{print $1}')
		local unit=$(echo $unique_size | awk '{print $3}')
		[ "$num" -lt "15" ]
		[ "$unit" == "MB" ]
	fi

  # launch a sys container with the committed image
  syscont=$(docker_run --rm image-commit)

  # verify testfile is present
  docker exec "$syscont" sh -c "cat /root/testfile"
  [ "$status" -eq 0 ]
  [[ "$output" == "testdata" ]]

  docker exec -d "$syscont" sh -c "containerd > /var/log/containerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_containerd $syscont

  # verify images are present
  docker exec "$syscont" sh -c 'ctr image ls -q'
  [ "$status" -eq 0 ]

  images="$output"

  run sh -c "echo \"$images\" | grep busybox"
  [ "$status" -eq 0 ]

  run sh -c "echo \"$images\" | grep alpine"
  [ "$status" -eq 0 ]

  # run an inner container using one of the embedded images
  docker exec "$syscont" sh -c "ctr container create ${CTR_IMG_REPO}/alpine:latest demo"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "ctr container ls -q"
  [ "$status" -eq 0 ]
  [[ "$output" == "demo" ]]

  # cleanup
  docker_stop "$syscont"
  docker image rm image-commit
}

@test "build with inner containerd images" {

  if sysbox_using_rootfs_cloning; then
	  skip "docker build with sysbox does not work without shiftfs or kernel 5.19+"
  fi

  # do a docker build with appropriate dockerfile
  pushd .
  cd tests/cind
  DOCKER_BUILDKIT=0 docker build --no-cache -t sc-with-inner-ctrd-img:latest .
  [ "$status" -eq 0 ]

  docker image prune -f
  [ "$status" -eq 0 ]
  popd

  # run generated container to confirm that images are embedded in it
  local syscont=$(docker_run --rm sc-with-inner-ctrd-img:latest tail -f /dev/null)

  docker exec -d "$syscont" sh -c "containerd > /var/log/containerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_containerd $syscont

  docker exec "$syscont" sh -c 'ctr image ls -q'
  [ "$status" -eq 0 ]

  images="$output"

  run sh -c "echo \"$images\" | grep busybox"
  [ "$status" -eq 0 ]

  run sh -c "echo \"$images\" | grep alpine"
  [ "$status" -eq 0 ]

  # run an inner container using one of the embedded images
  docker exec "$syscont" sh -c "ctr container create ${CTR_IMG_REPO}/alpine:latest demo"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "ctr container ls -q"
  [ "$status" -eq 0 ]
  [[ "$output" == "demo" ]]

  # cleanup
  docker_stop "$syscont"
  docker image rm sc-with-inner-ctrd-img:latest
  docker image prune -f
}
