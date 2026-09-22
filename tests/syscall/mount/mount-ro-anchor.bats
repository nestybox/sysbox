#!/usr/bin/env bats

#
# Verify that read-only bind mounts sysbox-runc sets up on sysbox-mgr's
# behalf -- plain user "-v host:container:ro" mounts -- are anchored (see
# setupRoAnchor() in sysbox-mgr) so that, just like sysbox's kernel-header
# /module mounts (see tests/syscall/mount/mount-immutables.bats), they
# can't be made read-write via mount_setattr(2) or other mount APIs
# sysbox-fs doesn't mediate.
#
# Unlike the kernel-header/module case, this protection applies to *any*
# read-only bind mount, so ordinary "docker -v ro" tests aren't safe to
# reuse: they only exercise mount(2)/umount2(2), which sysbox-fs already
# mediates regardless of anchoring.
#

load ../../helpers/run
load ../../helpers/docker
load ../../helpers/environment
load ../../helpers/mounts
load ../../helpers/sysbox
load ../../helpers/sysbox-health

function teardown() {
  sysbox_log_check
}

# Testcase #1.
#
# Build the mount-setattr-test helper binary; it issues mount_setattr(2)
# directly, bypassing sysbox-fs's mount(2)/umount2(2) syscall mediation
# entirely.
@test "mount-setattr-test prep -- ro-anchor" {
  pushd tests/syscall/mount/mount-setattr-test
  make
  popd
}

# Testcase #2.
#
# The ordinary read-only bind mount case: a plain "-v host:container:ro".
@test "plain -v ro mount can't be unlocked via mount_setattr(2)" {

  local host_dir=$(mktemp -d)
  chmod 755 ${host_dir}
  echo "data" > ${host_dir}/tfile

  local syscont=$(docker_run --rm \
    -v ${SYSBOX_ROOT}/tests/syscall/mount/mount-setattr-test:/mnt/mount-setattr-test \
    -v ${host_dir}:/mnt/rotest:ro \
    ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)

  local test_bin=/mnt/mount-setattr-test/mount-setattr-test

  docker exec ${syscont} sh -c "[ -x ${test_bin} ]"
  [ "$status" -eq 0 ]

  # Sanity check: the mount is genuinely read-only to start with.
  docker exec ${syscont} sh -c "touch /mnt/rotest/canary"
  [ "$status" -ne 0 ]

  docker exec ${syscont} sh -c "${test_bin} /mnt/rotest"
  [ "$status" -ne 0 ]

  # Still read-only after the mount_setattr(2) attempt.
  docker exec ${syscont} sh -c "touch /mnt/rotest/canary"
  [ "$status" -ne 0 ]

  docker_stop ${syscont}
  rm -rf ${host_dir}
}

# Testcase #3.
#
# Clean up the mount-setattr-test helper binary.
@test "mount-setattr-test cleanup -- ro-anchor" {
  pushd tests/syscall/mount/mount-setattr-test
  make clean
  popd
}
