#!/bin/bash

load ../helpers/run

#
# Docker Test Helper Functions
#
# Note: for tests using bats.
#

function wait_for_inner_dockerd {
  local syscont=$1
  retry_run 10 1 "__docker exec $syscont docker ps"
}

function docker_cont_ip() {
  local cont=$1
  local ip=$(__docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $cont)
  echo $ip
}
