#!/usr/bin/env bats

#
# Verify that clone() with new namespaces (CLONE_NEWPID, CLONE_NEWNET, etc.)
# works inside the sys container without problem.
#

load ../helpers/run
load ../helpers/docker
load ../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

# Verify that mount syscall emulation performs correct path resolution (per path_resolution(7))
@test "clone new namespaces" {

  local syscont=$(docker_run --rm ubuntu:latest tail -f /dev/null)

  docker exec "$syscont" bash -c "apt-get update && apt-get install --no-install-recommends -y libcap2"
  [ "$status" -eq 0 ]

  # The "userns_child_exec" program (borrowed from "The Linux Programming
  # Interface" book examples (Kerrisk)) performs a clone() into a configurable
  # set of new namespaces.

  docker cp /usr/bin/userns_child_exec "$syscont:/usr/bin/userns_child_exec"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "userns_child_exec -nmipuC echo success"
  [ "$status" -eq 0 ]

  docker_stop "$syscont"
}
