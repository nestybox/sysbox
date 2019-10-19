#!/usr/bin/env bats

#
# Test for building sys containers images with docker images inside
#

load ../helpers/run

SYSCONT_NAME=""

function wait_for_nested_dockerd {
  retry_run 10 1 eval "__docker exec $SYSCONT_NAME docker ps"
}

@test "build sys-cont with inner images" {

  # reconfigure default docker runtime in the host

  # dockerd_stop
  # cp /etc/docker/daemon.json /etc/docker/daemon.json.bak
  # (cat /etc/docker/daemon.json 2>/dev/null || echo '{}') | jq '. + {"default-runtime": "sysbox-runc"}' > /tmp/tmp.json
  # mv /tmp/tmp.json /etc/docker/daemon.json
  # dockerd_start

  # do a docker build with appropriate dockerfile
  pushd .
  cd tests/docker
  docker build --no-cache -t nestybox/sc-with-inner-img:latest .

  # run generated container
  SYSCONT_NAME=$(docker_run --rm nestybox/sc-with-inner-img:latest tail -f /dev/null)

  # confirm that images are embedded in it
  docker exec "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd-log 2>&1 &"
  [ "$status" -eq 0 ]

  wait_for_nested_dockerd

  docker exec "$SYSCONT_NAME" sh -c 'docker image ls --format "{{.Repository}}"'
  [ "$status" -eq 0 ]

  images="$output"

  run echo "$images"
  [ "$status" -eq 0 ]

  run sh -c "echo \"$images\" | grep busybox"
  [ "$status" -eq 0 ]

  run sh -c "echo \"$images\" | grep alpine"
  [ "$status" -eq 0 ]

  # run an inner container using one of the embedded images
  docker exec "$SYSCONT_NAME" sh -c "docker run --rm -d busybox tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "docker ps --format \"{{.ID}}\""
  [ "$status" -eq 0 ]
  INNER_CONT_NAME="$output"

  docker exec "$SYSCONT_NAME" sh -c "docker exec $INNER_CONT_NAME sh -c \"busybox | head -1\""
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ "BusyBox" ]]

  # cleanup
  docker_stop "$SYSCONT_NAME"
  popd

  # revert dockerd config
  # dockerd_stop
  # mv /etc/docker/daemon.json.bak /etc/docker/daemon.json
  # dockerd_start
}
