#!/usr/bin/env bats

# Testing of procLoadavg handler.

load ../helpers/fs
load ../helpers/run
load ../helpers/sysbox
load ../helpers/sysbox-health

function setup() {
  setup_busybox
}

function teardown() {
  teardown_busybox syscont
  sysbox_log_check
}

# Lookup/Getattr operation.
@test "procLoadavg lookup() operation" {

  skip "not a sysbox-fs mount yet"

  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "ls -l /proc/loadavg"
  [ "$status" -eq 0 ]

  verify_root_ro "${output}"
}
