#!/usr/bin/env bats

#
# Basic tests running docker inside a system container
#

load ../helpers/run

SYSCONT_NAME=""

function setup() {
  SYSCONT_NAME=$(docker_run nestybox/sys-container:debian-plus-docker tail -f /dev/null)
}

function teardown() {
  docker_stop "$SYSCONT_NAME"
}

function wait_for_nested_dockerd {
  retry_run 10 1 eval "docker exec $SYSCONT_NAME docker ps"
}

@test "basic sys container" {
  docker exec "$SYSCONT_NAME" hostname syscont
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" hostname
  [ "$status" -eq 0 ]
  [ "$output" = "syscont" ]
}

@test "basic inner docker" {
  docker exec "$SYSCONT_NAME" sh -c "dockerd > /var/log/dockerd-log 2>&1 &"
  [ "$status" -eq 0 ]

  wait_for_nested_dockerd

  docker exec "$SYSCONT_NAME" sh -c "docker run hello-world | grep \"Hello from Docker!\""
  [ "$status" -eq 0 ]
}

@test "basic inner busybox" {
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
}
