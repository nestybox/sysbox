#!/usr/bin/env bats

#
# Basic tests running sys containers with docker
#

load ../helpers/run

@test "basic sys container" {
  SYSCONT_NAME=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$SYSCONT_NAME" hostname syscont
  [ "$status" -eq 0 ]

  docker exec "$SYSCONT_NAME" hostname
  [ "$status" -eq 0 ]
  [ "$output" = "syscont" ]

  docker_stop "$SYSCONT_NAME"
}

@test "docker --init" {
  SYSCONT_NAME=$(docker_run --init --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$SYSCONT_NAME" pstree
  [ "$status" -eq 0 ]
  [[ "$output" == "docker-init---tail" ]]

  docker_stop "$SYSCONT_NAME"
}
