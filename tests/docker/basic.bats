#!/usr/bin/env bats

#
# Basic tests running sys containers with docker
#

load ../helpers/run

SYSCONT_NAME=""

function setup() {
  SYSCONT_NAME=$(docker_run nestybox/sys-container:debian-plus-docker tail -f /dev/null)
}

function teardown() {
  docker_stop "$SYSCONT_NAME"
}

@test "basic sys container" {
  docker exec "$SYSCONT_NAME" hostname syscont
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" hostname
  [ "$status" -eq 0 ]
  [ "$output" = "syscont" ]
}
