#!/usr/bin/env bats

#
# Basic tests running sys containers with docker
#

load ../helpers/run
load ../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

@test "basic sys container" {
  local syscont=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont" hostname syscont
  [ "$status" -eq 0 ]

  docker exec "$syscont" hostname
  [ "$status" -eq 0 ]
  [ "$output" = "syscont" ]

  docker_stop "$syscont"
}

@test "docker --init" {
  local syscont=$(docker_run --init --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont" pstree
  [ "$status" -eq 0 ]
  [[ "$output" == "docker-init---tail" ]]

  docker_stop "$syscont"
}
