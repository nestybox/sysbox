#!/usr/bin/env bats

#
# Basic tests running docker inside a system container
#

load ../helpers/run
load ../helpers/docker
load ../helpers/dind
load ../helpers/environment
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

  local inner_docker_graphdriver=$(get_inner_docker_graphdriver)

  docker exec "$SYSCONT_NAME" sh -c "grep \"graphdriver(s)=$inner_docker_graphdriver\" /var/log/dockerd.log"
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "docker run ${CTR_IMG_REPO}/hello-world | grep \"Hello from Docker!\""
  [ "$status" -eq 0 ]

  docker_stop "$SYSCONT_NAME"
}

@test "dind busybox" {

  SYSCONT_NAME=$(docker_run --rm ${CTR_IMG_REPO}/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec -d "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $SYSCONT_NAME

  local inner_docker_graphdriver=$(get_inner_docker_graphdriver)

  docker exec "$SYSCONT_NAME" sh -c "grep \"graphdriver(s)=$inner_docker_graphdriver\" /var/log/dockerd.log"
  [ "$status" -eq 0 ]

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

  local inner_docker_graphdriver=$(get_inner_docker_graphdriver)

  docker exec "$SYSCONT_NAME" sh -c "grep \"graphdriver(s)=$inner_docker_graphdriver\" /var/log/dockerd.log"
  [ "$status" -eq 0 ]

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

@test "dind docker with non-default data-root" {

  # Create a new docker image with a custom docker config.
  pushd .
  cd tests/dind
  docker build -t sc-with-non-default-docker-data-root:latest -f Dockerfile.docker-data-root .
  [ "$status" -eq 0 ]

  docker image prune -f
  [ "$status" -eq 0 ]
  popd

  # Launch a sys container.
  local syscont=$(docker_run --rm sc-with-non-default-docker-data-root:latest tail -f /dev/null)

  # Verify that the default '/var/lib/docker' mountpoint has now been replaced
  # by the the new docker data-root entry.
  docker exec "$syscont" sh -c "mount | egrep -q \"on \/var\/lib\/docker\""
  [ "$status" -ne 0 ]
  docker exec "$syscont" sh -c "mount | egrep -q \"on \/var\/lib\/different-docker-data-root\""
  [ "$status" -eq 0 ]

  # Initialize docker and verify that the new data-root has been honored.

  docker exec -d "$syscont" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_inner_dockerd $syscont

  docker exec "$syscont" sh -c "docker info | egrep -q \"different-docker-data-root\""
  [ "$status" -eq 0 ]

  # Verify that content can be properly stored in the new data-root by fetching
  # a new container image, and by checking that an inner container operates as
  # expected.
  docker exec "$syscont" sh -c "docker run --rm -d ${CTR_IMG_REPO}/busybox tail -f /dev/null"
  [ "$status" -eq 0 ]

  docker exec "$syscont" sh -c "docker ps --format \"{{.ID}}\""
  [ "$status" -eq 0 ]
  local inner_cont="$output"

  docker exec "$syscont" sh -c "docker exec $inner_cont sh -c \"busybox | head -1\""
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ "BusyBox" ]]

  # Cleaning up.
  docker_stop "$syscont"
  docker image rm sc-with-non-default-docker-data-root:latest
  docker image prune -f
}
