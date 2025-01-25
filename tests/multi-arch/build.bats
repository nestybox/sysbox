#!/usr/bin/env bats

#
# Test binfmt_misc inside Sysbox containers
#

load ../helpers/run
load ../helpers/docker
load ../helpers/environment
load ../helpers/sysbox-health
load ../helpers/multiarch

function setup() {
  if ! binfmt_misc_module_present; then
    skip "binfmt_misc module not present in kernel."
  fi

  if ! kernel_supports_binfmt_misc_namespacing; then
    skip "binfmt_misc not namespaced in kernel."
  fi
}

function teardown() {
  sysbox_log_check
}

@test "Docker cross-platform build inside a Sysbox container" {

  if [[ $(get_platform) != "amd64" ]]; then
     skip "test meant for amd64 architecture"
  fi

  # Start a Sysbox container with Docker inside
  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont

  # install docker multi-arch support inside the Sysbox container
  docker exec "$syscont" sh -c "docker run --rm --privileged multiarch/qemu-user-static --reset -p yes"
  [ "$status" -eq 0 ]

  # verify the installation worked; it takes a bit of time, so retry the command until it succeeds.
  retry_run 20 1 __docker exec "$syscont" sh -c 'docker buildx inspect --bootstrap | grep "Platforms" | grep "linux/arm64"'

  # create a dummy Dockerfile inside the container
  docker exec "$syscont" sh -c 'mkdir -p /root/test && echo "FROM alpine:latest" > /root/test/Dockerfile'
  [ "$status" -eq 0 ]

  # use Docker buildx to build a cross-platform image
  docker exec "$syscont" sh -c 'cd /root/test && docker buildx build --platform linux/arm64 -t alpine-arm-test:arm64 .'
  [ "$status" -eq 0 ]

  # verify the image works
  docker exec "$syscont" sh -c 'docker run --rm --platform linux/arm64 alpine-arm-test:arm64 uname -m'
  [ "$status" -eq 0 ]
  [[ "$output" == "aarch64" ]]

  docker_stop "$syscont"
}
