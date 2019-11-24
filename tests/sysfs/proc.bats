#!/usr/bin/env bats

# General tests of /proc handlers
#
# Handler-specific tests are under the proc<Handler>.bats file.

load ../helpers/fs
load ../helpers/run

function setup() {
  setup_busybox
}

function teardown() {
  teardown_busybox syscont
}

@test "proc lookup" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  for file in $SYSFS_PROC; do
    sv_runc exec syscont sh -c "ls -l $file"
    [ "$status" -eq 0 ]
    verify_root_ro "${output}"
  done
}

@test "proc read-only" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  for file in $SYSFS_PROC; do
    sv_runc exec syscont sh -c "echo \"data\" > $file"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Permission denied" ]]
  done
}

@test "procfs remount" {
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  # mounting procfs within the sys container works, but the
  # container's userns prevents access to system-wide resources
  sv_runc exec syscont sh -c "mkdir /root/proc && mount -t proc proc /root/proc"
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "echo 1 > /root/proc/sys/kernel/sysrq"
  [ "$status" -eq 1 ]
  [[ "$output" =~ /root/proc/sys/kernel/sysrq:\ Permission\ denied ]]

  sv_runc exec syscont sh -c "umount /root/proc"
  [ "$status" -eq 0 ]
}
