#!/usr/bin/env bats

#
# Docker compose inside a system container
#

load ../helpers/run

SYSCONT_NAME=""

function wait_for_nested_dockerd {
  retry_run 10 1 eval "__docker exec $SYSCONT_NAME docker ps"
}

@test "compose basic" {

  # this yaml file will be passed into the system container via a bind-mount
  file="/root/docker-compose.yml"

  cat << EOF > ${file}
version: '3'
services:
  alpine:
    image: "alpine"
    command: "tail -f /dev/null"
  busybox:
    image: "busybox"
    command: "tail -f /dev/null"
EOF

  SYSCONT_NAME=$(docker_run --rm --mount type=bind,source="${file}",target=/mnt/docker-compose.yml nestybox/ubuntu-disco-compose:latest tail -f /dev/null)

  docker exec -d "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd.log 2>&1"
  [ "$status" -eq 0 ]

  wait_for_nested_dockerd

  docker exec "$SYSCONT_NAME" sh -c "cd /mnt && docker-compose up -d"
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "docker ps --format \"{{.ID}}\" | wc -l"
  [ "$status" -eq 0 ]
  [[ "$output" == "2" ]]

  docker exec "$SYSCONT_NAME" sh -c "cd /mnt && docker-compose down -t0"
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" sh -c "docker ps --format \"{{.ID}}\" | wc -l"
  [ "$status" -eq 0 ]
  [[ "$output" == "0" ]]

  docker_stop "$SYSCONT_NAME"
  rm "$file"
}
