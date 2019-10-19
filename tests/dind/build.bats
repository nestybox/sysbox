#!/usr/bin/env bats

#
# Test for creating sys containers images with docker images inside
#

load ../helpers/run

SYSCONT_NAME=""

function wait_for_nested_dockerd {
  retry_run 10 1 eval "__docker exec $SYSCONT_NAME docker ps"
}

@test "build with inner images" {

  # Reconfigure default docker runtime in the host to sysbox-runc
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
  docker build --no-cache -t nestybox/sc-with-inner-img:latest .
  [ "$status" -eq 0 ]

  # run generated container
  SYSCONT_NAME=$(docker_run --rm nestybox/sc-with-inner-img:latest tail -f /dev/null)

  # confirm that images are embedded in it
  docker exec "$SYSCONT_NAME" sh -c "rm -f /var/run/docker.pid && dockerd > /var/log/dockerd-log 2>&1 &"
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
  docker image rm nestybox/sc-with-inner-img:latest
  docker image prune -f
  popd

  # revert dockerd config
  # dockerd_stop
  # mv /etc/docker/daemon.json.bak /etc/docker/daemon.json
  # dockerd_start
}

@test "commit with inner images" {

  SYSCONT_NAME=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd-log 2>&1 &"
  [ "$status" -eq 0 ]

  wait_for_nested_dockerd

  docker exec "$SYSCONT_NAME" sh -c "docker pull busybox:latest"
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "docker pull alpine:latest"
  [ "$status" -eq 0 ]

  # commit the sys container image
  docker commit "$SYSCONT_NAME" nestybox/alpine-docker-dbg:commit
  [ "$status" -eq 0 ]

  docker_stop "$SYSCONT_NAME"
  docker image prune -f

  # launch a sys container with the committed image
  SYSCONT_NAME=$(docker_run --rm nestybox/alpine-docker-dbg:commit)

  # make sure to remove docker.pid before launching docker (it's in the committed image)
  docker exec "$SYSCONT_NAME" sh -c "rm -f /var/run/docker.pid && dockerd > /var/log/dockerd-log 2>&1 &"
  [ "$status" -eq 0 ]

  wait_for_nested_dockerd

  # verify images are present
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
  docker image rm nestybox/alpine-docker-dbg:commit
}
