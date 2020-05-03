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

@test "docker --oom-score-adj" {

  # Sysbox sys containers have this oom adj range
  local oom_min_val=-999
  local oom_max_val=1000
  local syscont=""

  syscont=$(docker_run --rm nestybox/alpine-docker-dbg:latest tail -f /dev/null)

  # Verify default docker oom value is 0
  docker exec "$syscont" cat /proc/1/oom_score_adj
  [ "$status" -eq 0 ]
  [[ "$output" == "0" ]]

  # Verify oom range
  docker exec "$syscont" echo $oom_min_val > /proc/self/oom_score_adj
  [ "$status" -eq 0 ]

  docker exec "$syscont" echo $oom_max_val > /proc/self/oom_score_adj
  [ "$status" -eq 0 ]

  docker_stop "$syscont"

  # Verify override of default oom value
  local custom_val=-1
  syscont=$(docker_run --rm --oom-score-adj=$custom_val nestybox/alpine-docker-dbg:latest tail -f /dev/null)

  docker exec "$syscont" cat /proc/1/oom_score_adj
  [ "$status" -eq 0 ]
  [[ "$output" == "$custom_val" ]]

  docker_stop "$syscont"
}
