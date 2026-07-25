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
  # XXX: "docker cp" into this container intermittently fails with "openat
  # etc/resolv.conf: directory not empty" -- this reproduces even copying to
  # "/" (not just "/usr/bin"), regardless of whether it runs before or after
  # apt-get install above. It looks like a kernel/VFS interaction between
  # containerd's tar-based archive extraction (which "docker cp" uses) and
  # the idmapped mount sysbox sets up over /etc/resolv.conf. Avoid "docker
  # cp" entirely by piping the binary in via "docker exec -i" instead, which
  # doesn't hit this path.

  local arch=$(get_platform)

  run bash -c "docker exec -i \"$syscont\" sh -c 'cat > /usr/bin/userns_child_exec && chmod +x /usr/bin/userns_child_exec' < tests/bin/userns_child_exec_${arch}"
  [ "$status" -eq 0 ]

  docker exec "$syscont" bash -c "userns_child_exec -nmipuC echo success"
  [ "$status" -eq 0 ]

  docker_stop "$syscont"
}
