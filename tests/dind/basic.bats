#!/usr/bin/env bats

#
# Basic tests running docker inside a system container
#

load ../helpers/run
load ../helpers/docker
load ../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

SYSCONT_NAME=""

@test "dind basic" {

  SYSCONT_NAME=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec -d "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $SYSCONT_NAME

  docker exec "$SYSCONT_NAME" sh -c "docker run ${CTR_IMG_REPO}/hello-world | grep \"Hello from Docker!\""
  [ "$status" -eq 0 ]

  docker_stop "$SYSCONT_NAME"
}

@test "dind busybox" {

  SYSCONT_NAME=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec -d "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $SYSCONT_NAME

  docker exec "$SYSCONT_NAME" sh -c "docker run --rm -d ${CTR_IMG_REPO}/busybox tail -f /dev/null"
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
FROM ${CTR_IMG_REPO}/alpine
MAINTAINER Nestybox
RUN apk update && apk add nginx
COPY . /root
EXPOSE 8080
CMD ["echo","Image created"]
EOF

  SYSCONT_NAME=$(docker_run --rm --mount type=bind,source=${file},target=/mnt/Dockerfile ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec -d "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $SYSCONT_NAME

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
