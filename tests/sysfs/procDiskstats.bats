#!/usr/bin/env bats

# Testing of procDiskstats handler.

load ../helpers/fs
load ../helpers/run
load ../helpers/sysbox-health

function setup() {
  setup_busybox
}

function teardown() {
  teardown_busybox syscont
  sysbox_log_check
}

# Lookup/Getattr operation.
@test "procDiskstats lookup() operation" {

  skip "not a sysbox-fs mount yet"

  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "ls -l /proc/diskstats"
  [ "$status" -eq 0 ]

  verify_root_ro "${output}"
}
