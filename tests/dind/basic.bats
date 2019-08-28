#!/usr/bin/env bats

#
# Basic tests running docker inside a system container
#

load ../helpers/run

SYSCONT_NAME=""

function setup() {
  run_only_test "dind docker build"
}

function wait_for_nested_dockerd {
  retry_run 10 1 eval "__docker exec $SYSCONT_NAME docker ps"
}

@test "dind basic" {

  SYSCONT_NAME=$(docker_run --rm nestybox/sys-container:ubuntu-plus-docker tail -f /dev/null)

  docker exec "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd-log 2>&1 &"
  [ "$status" -eq 0 ]

  wait_for_nested_dockerd

  docker exec "$SYSCONT_NAME" sh -c "docker run hello-world | grep \"Hello from Docker!\""
  [ "$status" -eq 0 ]

  docker_stop "$SYSCONT_NAME"
}

@test "dind busybox" {

  SYSCONT_NAME=$(docker_run --rm nestybox/sys-container:ubuntu-plus-docker tail -f /dev/null)

  docker exec "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd-log 2>&1 &"
  [ "$status" -eq 0 ]

  wait_for_nested_dockerd

  docker exec "$SYSCONT_NAME" sh -c "docker run --rm -d busybox tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "docker ps --format \"{{.ID}}\""
  [ "$status" -eq 0 ]
  INNER_CONT_NAME="$output"

  docker exec "$SYSCONT_NAME" sh -c "docker exec $INNER_CONT_NAME sh -c \"busybox | head -1\""
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ "BusyBox" ]]

  docker_stop "$SYSCONT_NAME"
}

@test "dind docker build" {

  # this dockerfile will be passed into the system container via a bind-mount
  file="/root/Dockerfile"

  cat << EOF > ${file}
FROM debian:latest
MAINTAINER Nestybox
RUN apt-get update
RUN apt-get install -y nginx
COPY . /root
EXPOSE 8080
CMD ["echo","Image created"]
EOF

  SYSCONT_NAME=$(docker_run --rm --mount type=bind,source=${file},target=/mnt/Dockerfile nestybox/sys-container:ubuntu-plus-docker tail -f /dev/null)

  docker exec "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd-log 2>&1 &"
  [ "$status" -eq 0 ]

  wait_for_nested_dockerd

  image="test_nginx"

  docker exec "$SYSCONT_NAME" sh -c "cd /mnt && docker build -t ${image} ."
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "docker run ${image}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Image created" ]]

  docker_stop "$SYSCONT_NAME"
  docker image rm ${image}
  rm ${file}
}
