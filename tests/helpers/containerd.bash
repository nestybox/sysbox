#!/usr/bin/env bats

load $(dirname ${BASH_SOURCE[0]})/run.bash

#
# Containerd Test Helper Functions
#
# Note: for tests using bats.
#

function wait_for_inner_containerd {
  local syscont=$1
  retry_run 10 1 "__docker exec $syscont ctr -v"
}
