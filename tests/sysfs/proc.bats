#!/usr/bin/env bats

# General tests of proc handlers
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
