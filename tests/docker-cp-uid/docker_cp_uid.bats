#!/usr/bin/env bats

#
# Integration tests for "docker cp" uid:gid correctness in sysbox containers.
#
# Tests verify that files copied into a running sysbox container via "docker cp"
# appear with the correct uid:gid inside the container, regardless of whether
# the overlayfs upper layer is id-mapped (kernel >= 5.19) or chown-shifted
# (kernel < 5.19 fallback).
#
# Root cause fixed: docker cp wrote through the merged overlayfs mount as host
# uid 0, landing on disk with uid=0 in the upper layer. When only lower layers
# are id-mapped, uid=0 is outside the container userns mapping range, causing
# the kernel to return overflow uid 65534 (nobody:nogroup).
#
# Fix: on kernel >= 5.19, sysbox-runc now id-maps both the overlayfs upperdir
# and workdir with the same userns as the lower layers, so every write through
# the merged mount is translated by the kernel: writer uid 0 → disk uid X.
#
# NOTE: these tests require:
#   - Docker configured to use sysbox as the OCI runtime
#   - The host kernel version is exposed by $KERNEL_MAJOR.$KERNEL_MINOR
#   - Standard Sysbox test helpers (run, docker, uid-shift, sysbox-health)
#

load ../helpers/run
load ../helpers/docker
load ../helpers/uid-shift
load ../helpers/sysbox-health
load ../helpers/environment

function setup() {
  sysbox_log_check
}

function teardown() {
  sysbox_log_check
}

# ─── helpers ────────────────────────────────────────────────────────────────

# Returns 0 if the host kernel supports idmapped overlayfs upperdir (>= 5.19).
function kernel_supports_ovfs_upper_idmap() {
  local major minor
  major=$(uname -r | cut -d. -f1)
  minor=$(uname -r | cut -d. -f2)
  [ "$major" -gt 5 ] || { [ "$major" -eq 5 ] && [ "$minor" -ge 19 ]; }
}

# ─── docker cp → container ──────────────────────────────────────────────────

@test "docker cp: root-owned host file appears as root inside container" {
  #
  # Arrange: start a sysbox container, create a root-owned file on the host.
  #
  local syscont
  syscont=$(docker_run --rm nestybox/alpine tail -f /dev/null)
  [ "$status" -eq 0 ]

  local tmpfile
  tmpfile=$(mktemp)
  echo "hello sysbox" > "$tmpfile"
  # tmpfile is owned by the invoking user; chown to root for this test.
  chown root:root "$tmpfile"

  #
  # Act: copy the file into the container.
  #
  run docker cp "$tmpfile" "$syscont:/tmp/test-file"
  [ "$status" -eq 0 ]

  #
  # Assert: inside the container the file is owned by uid 0 (root), not nobody.
  # Before the fix this would show 65534:65534 (nobody:nogroup) on kernel >= 5.19.
  #
  run docker exec "$syscont" stat -c '%u:%g' /tmp/test-file
  [ "$status" -eq 0 ]
  [ "$output" = "0:0" ]

  rm -f "$tmpfile"
  docker_stop "$syscont"
}

@test "docker cp: user-owned host file appears with correct uid inside container" {
  #
  # A file owned by uid 1000 on the host should appear as uid 1000 inside the
  # container (assuming the container image has a user with uid 1000, or the
  # test just checks the numeric value).
  #
  local syscont
  syscont=$(docker_run --rm nestybox/alpine tail -f /dev/null)
  [ "$status" -eq 0 ]

  local tmpfile
  tmpfile=$(mktemp)
  echo "hello sysbox" > "$tmpfile"
  chown 1000:1000 "$tmpfile"

  run docker cp "$tmpfile" "$syscont:/tmp/user-file"
  [ "$status" -eq 0 ]

  run docker exec "$syscont" stat -c '%u:%g' /tmp/user-file
  [ "$status" -eq 0 ]
  [ "$output" = "1000:1000" ]

  rm -f "$tmpfile"
  docker_stop "$syscont"
}

# ─── docker cp ← container ──────────────────────────────────────────────────

@test "docker cp: file created inside container as root copies out with uid 0 on host" {
  #
  # A file created inside the container by root (container uid 0 = host uid X)
  # should copy out to the host with uid matching the invoking user (or root).
  #
  local syscont
  syscont=$(docker_run --rm nestybox/alpine tail -f /dev/null)
  [ "$status" -eq 0 ]

  run docker exec "$syscont" sh -c "echo hello > /tmp/container-file && chown 0:0 /tmp/container-file"
  [ "$status" -eq 0 ]

  local tmpdir
  tmpdir=$(mktemp -d)

  run docker cp "$syscont:/tmp/container-file" "$tmpdir/"
  [ "$status" -eq 0 ]

  # The copied file should be owned by root (uid 0) on the host side.
  local uid
  uid=$(stat -c '%u' "$tmpdir/container-file")
  [ "$uid" -eq 0 ]

  rm -rf "$tmpdir"
  docker_stop "$syscont"
}

# ─── pause / resume / restart ownership stability ────────────────────────────

@test "docker cp: ownership survives container pause and resume" {
  #
  # After pause/resume, previously docker-cp'd files must retain the correct
  # uid:gid inside the container. The pause/resume chown path was updated to
  # skip the upper layer when overlayfsUpperIDMap is active.
  #
  local syscont
  syscont=$(docker_run --rm nestybox/alpine tail -f /dev/null)
  [ "$status" -eq 0 ]

  # Copy a root-owned file in.
  local tmpfile
  tmpfile=$(mktemp)
  chown root:root "$tmpfile"
  run docker cp "$tmpfile" "$syscont:/tmp/pause-test"
  [ "$status" -eq 0 ]

  # Pause, then resume.
  run docker pause "$syscont"
  [ "$status" -eq 0 ]
  run docker unpause "$syscont"
  [ "$status" -eq 0 ]

  # File must still be root-owned inside the container.
  run docker exec "$syscont" stat -c '%u:%g' /tmp/pause-test
  [ "$status" -eq 0 ]
  [ "$output" = "0:0" ]

  rm -f "$tmpfile"
  docker_stop "$syscont"
}

@test "docker cp: ownership survives container stop and restart" {
  #
  # After stop/restart, docker-cp'd files must retain the correct uid:gid.
  # This exercises the unregister/re-register path in sysbox-mgr.
  #
  local syscont
  syscont=$(docker_run nestybox/alpine tail -f /dev/null)
  [ "$status" -eq 0 ]

  local tmpfile
  tmpfile=$(mktemp)
  chown root:root "$tmpfile"
  run docker cp "$tmpfile" "$syscont:/tmp/restart-test"
  [ "$status" -eq 0 ]

  run docker restart "$syscont"
  [ "$status" -eq 0 ]

  run docker exec "$syscont" stat -c '%u:%g' /tmp/restart-test
  [ "$status" -eq 0 ]
  [ "$output" = "0:0" ]

  rm -f "$tmpfile"
  docker rm -f "$syscont"
}
