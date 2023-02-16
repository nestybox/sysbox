#!/usr/bin/env bats

#
# Verify that clone() with new namespaces (CLONE_NEWPID, CLONE_NEWNET, etc.)
# works inside the sys container without problem.
#

load ../../helpers/run
load ../../helpers/docker
load ../../helpers/environment
load ../../helpers/sysbox-health
load ../../helpers/environment

function teardown() {
  sysbox_log_check
}

@test "clone new namespaces" {

  local syscont=$(docker_run --rm ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)

  docker exec "$syscont" bash -c "apt-get update && apt-get install --no-install-recommends -y libcap2"
  [ "$status" -eq 0 ]

  # The "userns_child_exec" program (borrowed from "The Linux Programming
  # Interface" book examples (Kerrisk)) performs a clone() into a configurable
  # set of new namespaces.
  #
  # XXX: for some reason "docker cp" fails to copy to /usr/bin in this
  # container; not sure why since there is nothing special about that dir (no
  # mounts on it, no symlinks, etc.) I think it's a problem with "tar" used by
  # docker cp, possibly related to an ID-mapped rootfs. To work-around this, we
  # copy userns_child_exec to the container's "/" and then move it to "/usr/bin".

  local arch=$(get_platform)

  docker cp tests/bin/userns_child_exec_${arch} "$syscont:/userns_child_exec"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "mv /userns_child_exec /usr/bin/."
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "userns_child_exec -nmipuC echo success"
  [ "$status" -eq 0 ]

  docker_stop "$syscont"
}
