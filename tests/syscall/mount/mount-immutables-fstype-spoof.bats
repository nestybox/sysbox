#!/usr/bin/env bats

#
# Verify that a spoofed mount(2) "fstype" argument can't be used to bypass
# sysbox's immutable read-only mount protection.
#
# Background: for MS_REMOUNT, the kernel ignores the "source" and
# "filesystemtype" arguments of mount(2) (see mount(2)); it only uses
# "target" and the mount flags. sysbox-fs used to trust the tracee-supplied
# "fstype" to recognize (and skip its immutable-mount checks for) procfs and
# sysfs remounts. A container process could exploit this by passing
# fstype="proc" (or "sysfs") while targeting an unrelated read-only immutable
# mount (e.g. the default /lib/modules/<kernel> host bind mount) to flip it
# read-write, bypassing the protection described in "immutable ro mount
# can't be remounted rw" (see mount-immutables.bats).
#
# Testcase #2 below is a literal reproduction of the reported issue (the
# exact mount and fstype value involved). The remaining testcases sweep a
# broader set of mounts and fstype values for defense-in-depth regression
# coverage.
#

load ../../helpers/run
load ../../helpers/syscall
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
# Build the remount-fstype-spoof-test helper binary; it issues a raw
# mount(NULL, target, fstype, MS_REMOUNT|MS_BIND, NULL) syscall, with
# control over the exact "fstype" value (including a genuine NULL
# pointer, which the "mount" CLI and Go's higher-level mount wrappers
# can't express).
@test "remount-fstype-spoof test prep" {
  pushd tests/syscall/mount/remount-fstype-spoof
  make
  popd
}

# Testcase #2.
#
# Literal reproduction of the originally-reported issue: a process with
# CAP_SYS_ADMIN spoofs fstype="proc" while remounting the sys container's
# default read-only /usr/lib/modules/<kernel-release> host bind mount (the
# one sysbox itself sets up), attempting to flip it read-write. This
# specific mount and fstype value are what makes this a genuine
# reproduction, as opposed to the more abstract fstype-sweep coverage in
# the testcases below.
@test "spoofed fstype=proc reproduces the reported /lib/modules bypass" {

  local syscont=$(docker_run --rm \
    -v ${SYSBOX_ROOT}/tests/syscall/mount/remount-fstype-spoof:/mnt/remount-fstype-spoof \
    ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)

  local test_bin=/mnt/remount-fstype-spoof/remount-fstype-spoof-test

  docker exec ${syscont} sh -c "[ -x ${test_bin} ]"
  [ "$status" -eq 0 ]

  local kernel_rel=$(__docker exec ${syscont} sh -c "uname -r")
  local target="/usr/lib/modules/${kernel_rel}"

  # This mount depends on the host actually having modules for the
  # container's kernel release; skip (rather than silently pass) when it's
  # absent, since a pass without ever touching it wouldn't reproduce
  # anything.
  local immutable_ro_mounts=$(list_container_ro_mounts ${syscont} "0" "/")
  if ! grep -qxF "${target}" <<< "${immutable_ro_mounts}"; then
    docker_stop ${syscont}
    skip "${target} is not a read-only mount in this container"
  fi

  local remounts_allowed
  run allow_immutable_remounts
  if [ "${status}" -eq 0 ]; then
    remounts_allowed=0
  else
    remounts_allowed=1
  fi

  printf "\nreproducing reported bypass: spoofed fstype=proc remount of ${target}\n"

  docker exec ${syscont} sh -c "${test_bin} -fstype proc ${target}"
  if [[ ${remounts_allowed} -eq 0 ]]; then
    [ "$status" -eq 0 ]
    # Verify the mount is now genuinely read-write (not just that the
    # remount syscall reported success).
    docker exec ${syscont} sh -c "touch ${target}/canary && rm -f ${target}/canary"
    [ "$status" -eq 0 ]
  else
    [ "$status" -ne 0 ]
    docker exec ${syscont} sh -c "touch ${target}/canary"
    [ "$status" -ne 0 ]
  fi

  docker_stop ${syscont}
}

# Testcase #3.
#
# Ensure that a read-only immutable mount can't be remounted read-write by
# spoofing the mount(2) "fstype" argument, regardless of the value used
# (a real fstype that sysbox-fs treats specially, an unrelated fstype, or a
# NULL fstype), if and only if sysbox-fs is running with the
# 'allow-immutable-remounts' option disabled (the default). Alternatively,
# verify that all such remounts are allowed.
@test "spoofed fstype can't bypass immutable ro remount protection" {

  local syscont=$(docker_run --rm \
    -v ${SYSBOX_ROOT}/tests/syscall/mount/remount-fstype-spoof:/mnt/remount-fstype-spoof \
    ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)

  local test_bin=/mnt/remount-fstype-spoof/remount-fstype-spoof-test

  # Guard against a missing/non-executable test_bin silently turning into a
  # false pass below (a "command not found" docker-exec failure also
  # satisfies a "remount was rejected" check).
  docker exec ${syscont} sh -c "[ -x ${test_bin} ]"
  [ "$status" -eq 0 ]

  local immutable_ro_mounts=$(list_container_ro_mounts ${syscont} "0" "/")
  run is_list_empty ${immutable_ro_mounts}
  [ "$status" -ne 0 ]

  # Determine the mode in which to operate.
  local remounts_allowed
  run allow_immutable_remounts
  if [ "${status}" -eq 0 ]; then
    remounts_allowed=0
  else
    remounts_allowed=1
  fi

  # "NULL" instructs the helper binary to pass a genuine NULL fstype
  # pointer; it's the negative control that proves any bypass is caused
  # specifically by the proc/sysfs spoof (and not some broader failure of
  # the immutable-mount protection).
  local spoof_fstypes=("proc" "sysfs" "ext4" "NULL")

  for m in ${immutable_ro_mounts}; do
    # Skip /proc and /sys since these are special mounts with their own
    # dedicated remount tests (see mount-procfs.bats, mount-sysfs.bats).
    if [[ ${m} =~ "/proc" ]] || [[ ${m} =~ "/proc/*" ]] ||
        [[ ${m} =~ "/sys" ]] || [[ ${m} =~ "/sys/*" ]]; then
        continue
    fi

    for fstype in "${spoof_fstypes[@]}"; do
      printf "\ntesting rw remount of immutable ro mount ${m} with spoofed fstype=${fstype}\n"

      docker exec ${syscont} sh -c "${test_bin} -fstype ${fstype} ${m}"
      if [[ ${remounts_allowed} -eq 0 ]]; then
        [ "$status" -eq 0 ]
        # Verify mountpoint is now read-write.
        docker exec ${syscont} sh -c "touch ${m}"
        [ "$status" -eq 0 ]
      else
        [ "$status" -ne 0 ]
        # Verify mountpoint continues to be read-only.
        docker exec ${syscont} sh -c "touch ${m}"
        [ "$status" -ne 0 ]
      fi
    done
  done

  local immutable_ro_mounts_after=$(list_container_ro_mounts ${syscont} "0" "/")
  if [[ ${remounts_allowed} -eq 0 ]]; then
    [[ $immutable_ro_mounts != $immutable_ro_mounts_after ]]
  else
    [[ $immutable_ro_mounts == $immutable_ro_mounts_after ]]
  fi

  docker_stop ${syscont}
}

# Testcase #4.
#
# Ensure that a read-only immutable mount can't be bind-mounted to a new
# mountpoint and then remounted read-write there by spoofing the mount(2)
# "fstype" argument, if and only if sysbox-fs is running with the
# 'allow-immutable-remounts' option disabled (the default). Alternatively,
# verify that this remount is allowed.
@test "spoofed fstype can't bypass immutable ro bind-mount protection" {

  local syscont=$(docker_run --rm \
    -v ${SYSBOX_ROOT}/tests/syscall/mount/remount-fstype-spoof:/mnt/remount-fstype-spoof \
    ${CTR_IMG_REPO}/ubuntu:latest tail -f /dev/null)

  local test_bin=/mnt/remount-fstype-spoof/remount-fstype-spoof-test

  # Guard against a missing/non-executable test_bin silently turning into a
  # false pass below (a "command not found" docker-exec failure also
  # satisfies a "remount was rejected" check).
  docker exec ${syscont} sh -c "[ -x ${test_bin} ]"
  [ "$status" -eq 0 ]

  local immutable_ro_mounts=$(list_container_ro_mounts ${syscont} "0" "/")
  run is_list_empty ${immutable_ro_mounts}
  [ "$status" -ne 0 ]
  local target=/root/target

  local remounts_allowed
  run allow_immutable_remounts
  if [ "${status}" -eq 0 ]; then
    remounts_allowed=0
  else
    remounts_allowed=1
  fi

  for m in ${immutable_ro_mounts}; do
    # Skip /proc and /sys since these are special mounts with their own
    # dedicated bind-mount tests (see mount-procfs.bats, mount-sysfs.bats).
    if [[ ${m} =~ "/proc" ]] || [[ ${m} =~ "/proc/*" ]] ||
       [[ ${m} =~ "/sys" ]] || [[ ${m} =~ "/sys/*" ]]; then
       continue
    fi

    printf "\ntesting spoofed-fstype rw remount of immutable ro bind-mount of ${m}\n"

    # Create bind-mount target (dir or file, depending on bind-mount source type).
    docker exec ${syscont} bash -c "[[ -d ${m} ]]"
    if [ "$status" -eq 0 ]; then
      docker exec ${syscont} sh -c "mkdir -p $target"
      [ "$status" -eq 0 ]
    else
      docker exec ${syscont} sh -c "touch $target"
      [ "$status" -eq 0 ]
    fi

    docker exec ${syscont} sh -c "mount --bind ${m} $target"
    [ "$status" -eq 0 ]

    # Verify the bind-mount continues to be read-only.
    docker exec ${syscont} sh -c "touch $target"
    [ "$status" -ne 0 ]

    docker exec ${syscont} sh -c "${test_bin} -fstype proc $target"
    if [[ ${remounts_allowed} -eq 0 ]]; then
      [ "$status" -eq 0 ]
      docker exec ${syscont} sh -c "touch $target"
      [ "$status" -eq 0 ]
    else
      [ "$status" -ne 0 ]
      docker exec ${syscont} sh -c "touch $target"
      [ "$status" -ne 0 ]
    fi

    docker exec ${syscont} sh -c "umount $target && rm -rf $target"
    [ "$status" -eq 0 ]
  done

  docker_stop ${syscont}
}

# Testcase #5.
#
# Clean up the remount-fstype-spoof-test helper binary.
@test "remount-fstype-spoof test cleanup" {
  pushd tests/syscall/mount/remount-fstype-spoof
  make clean
  popd
}
