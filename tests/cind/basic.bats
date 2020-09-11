#!/usr/bin/env bats

#
# Basic tests running containerd inside a system container
#

load ../helpers/run
load ../helpers/containerd
load ../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

@test "cind basic" {

  syscont=$(docker_run --rm nestybox/ubuntu-bionic-docker-dbg:latest tail -f /dev/null)

  docker exec -d "$syscont" sh -c "containerd > /var/log/containerd.log --log-level=debug 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_containerd $syscont

  docker exec "$syscont" sh -c "ctr image pull docker.io/library/hello-world:latest"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "ctr image ls -q"
  [ "$status" -eq 0 ]
  [[ "$output" == "docker.io/library/hello-world:latest" ]]

  docker exec "$syscont" sh -c "ctr container create docker.io/library/hello-world:latest demo"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "ctr container ls -q"
  [ "$status" -eq 0 ]
  [[ "$output" == "demo" ]]

  docker exec "$syscont" sh -c "ctr container delete demo"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "ctr image remove docker.io/library/hello-world:latest"
  [ "$status" -eq 0 ]
  [[ "$output" == "docker.io/library/hello-world:latest" ]]

  docker_stop "$syscont"
}

@test "commit with inner images" {

  local syscont=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec -d "$syscont" sh -c "containerd > /var/log/containerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_containerd $syscont

  docker exec "$syscont" sh -c "echo testdata > /root/testfile"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "ctr image pull docker.io/library/busybox:latest"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "ctr image pull docker.io/library/alpine:latest"
  [ "$status" -eq 0 ]

  # commit the sys container image
  docker image rm -f image-commit
  docker commit "$syscont" image-commit
  [ "$status" -eq 0 ]

  docker_stop "$syscont"
  docker image prune -f

  # verify the committed image has an appropriate size (slightly
  # bigger than the base image since it includes inner containerd busybox & alpine images)
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
  docker exec "$syscont" sh -c "ctr container create docker.io/library/alpine:latest demo"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "ctr container ls -q"
  [ "$status" -eq 0 ]
  [[ "$output" == "demo" ]]

  # cleanup
  docker_stop "$syscont"
  docker image rm image-commit
}

@test "build with inner containerd images" {

  # randomly pre-mount shiftfs on /lib/modules/<kernel-version>, to test whether the sysbox-mgr
  # shiftfs manager detects and skips mounting shiftfs on this directory

  # do a docker build with appropriate dockerfile
  pushd .
  cd tests/cind
  docker build --no-cache -t nestybox/sc-with-inner-ctrd-img:latest .
  [ "$status" -eq 0 ]

  docker image prune -f
  [ "$status" -eq 0 ]
  popd

  # run generated container to confirm that images are embedded in it
  local syscont=$(docker_run --rm nestybox/sc-with-inner-ctrd-img:latest tail -f /dev/null)

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
  docker exec "$syscont" sh -c "ctr container create docker.io/library/alpine:latest demo"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "ctr container ls -q"
  [ "$status" -eq 0 ]
  [[ "$output" == "demo" ]]

  # cleanup
  docker_stop "$syscont"
  docker image rm nestybox/sc-with-inner-ctrd-img:latest
  docker image prune -f
}
